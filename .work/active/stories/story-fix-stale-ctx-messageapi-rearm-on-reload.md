---
id: story-fix-stale-ctx-messageapi-rearm-on-reload
kind: story
stage: drafting
tags: [pi-extension, bug, lifecycle]
parent: epic-remote-session-resilience-refactor
feature_parent: feature-session-stable-message-delivery
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-03
updated: 2026-07-11
reverted_misguided_fix: 2026-07-03
spike_committed: 2026-07-11
---

# Stale `messageApi` after session replacement — runtime ownership coordinator

## Status: the root cause is corrected. Design settled; implementation open.

The prior "SDK-blocked" / "cancel-and-re-drive" framings were **disproven**
(2026-07-11, real-SDK probes + live log + four parallel deep investigations).
The actual defect is a **Remote Pi lifecycle ownership bug**, and it has a
fork-local extension-side fix. This story is re-scoped to that fix.

## Symptom (unchanged)

After a session replacement, the extension's `messageApi` (used to deliver
inbound phone messages to the agent) goes stale permanently — every subsequent
`user_message` from the phone throws `internal_error: Agent rejected incoming
message: …ctx is stale…`, then `agent session not bound yet`. Recovery
currently requires a workstation `/reload`, which a phone-only operator can't
trigger.

## Corrected root cause (verified 2026-07-11)

**Child `AgentSession` factories steal a module-global binding.**

Remote Pi stores delivery-critical state as **process-global module singletons**
in `pi-extension/src/index.ts`:

- `_sdkSessionProjection` (the `SdkSessionProjection` instance)
- `_pi` / `_messageApi` (the factory `ExtensionAPI`)
- `_lastEventCtx` / `_lastCtx` (event/command contexts)
- relay, mesh, owner-multiplexer, and lifecycle resources

Every extension factory invocation **immediately** does:

```ts
_sdkSessionProjection.bindApi(pi);   // index.ts:1273 (factory body)
```

…which overwrites the module-global `messageApi` slot
(`sdk_session_projection.ts:147` → `bindCapabilities`).

`@gotgenes/pi-subagents` (installed at `~/.pi/agent/npm/node_modules/@gotgenes/
pi-subagents`, v18.0.1) creates child `AgentSession`s **in the same Node
process**. Each child (`create-subagent-session.ts:177-233`):

1. Creates its own fresh `ResourceLoader` + extension runtime.
2. **Reuses the cached Remote Pi extension module/factory** (jiti module cache).
3. Invokes the factory with the **child's** `pi`.
4. The factory's `bindApi(childPi)` **overwrites the parent's `messageApi`**.
5. The child runs, then `childSession.dispose()` (`subagent-session.ts:193`)
   invalidates the child runtime → the stored child `pi` is now stale.
6. **Nothing re-arms the parent binding.** The parent session is still healthy;
   Remote Pi is just pointing at the disposed child.

This is permanent until a `/reload` (the only path that re-runs the factory
against the *parent* session and re-arms a non-stale API).

### Why the prior "stock CLI /new reuses a stale runtime" claim is false

The prior analysis traced `resourceLoader.getExtensions()` *inside one*
`AgentSession` and concluded `/new`/`/resume`/`/fork` reuse a cached, poisoned
runtime. It missed the **outer CLI runtime factory** in `main.js`: every
replacement calls the stored `createRuntime`, which creates **fresh services +
a fresh `DefaultResourceLoader`** (`main.js:489-501` in 0.80.6), which invokes
the cached extension factory with a **fresh runtime/API**.

Real RPC `/new` probes against **both** the installed host (0.80.6) and the
local compile dep (0.79.10) confirmed:

```
factory 1 → session_start(startup) → pi.appendEntry() succeeds
session_shutdown(new)
factory 2 → session_start(new) → fresh pi.appendEntry() succeeds
```

`appendEntry` exercises the same `runtime.assertActive()` guard as
`sendUserMessage`, without invoking a model. So stock Pi replacement already
provides a fresh, working factory API. The gap is Remote Pi's ownership, not
the SDK.

### Live evidence

`~/.pi/remote/debug/delivery.log` (2026-07-10/11) shows the child-factory
overwrite directly. While this investigation launched four parallel subagents,
the log recorded four rapid:

```
message_api_armed via: factory
session_lifecycle reason: startup, <fresh child session id>
```

— child factories overwriting the parent delivery slot in real time. A later
`message_api_null reason: stale` (15:46:53) followed, matching child disposal.

A minimal real-host reproduction (two `loadExtensionsCached` calls against the
host loader) confirmed the mechanism:

```
factoryCalls: 2
runtimes are distinct
module-global currentPi routes first to parent, then child
child runner.invalidate()
module-global currentPi throws CHILD_STALE
parent API remains active
```

## Rejected alternatives (do not re-litigate)

1. **"Re-arm from the factory `pi` on `session_start`"** (the reverted first
   fix). The factory `pi` IS re-armed fresh by stock replacement — but a child
   factory overwrites it before the parent's `session_start` can matter. Mocks
   passed; live failed. Reverted.
2. **Cancel-and-re-drive via `session_before_switch`** (the "Fork-local
   redesign" in prior revisions). **Disproven by spike (commit `d554f13`):**
   `ExtensionRunner.emit()` (`runner.js:522`) builds the handler ctx via
   `createContext()` (the plain `ExtensionContext`), **not**
   `createCommandContext()`. The event ctx has **no** `newSession`/`fork`/
   `switchSession`/`navigateTree`/`reload`. The handler cannot re-drive a
   replacement. `/fork` is also a separate `session_before_fork` event. See
   the spike section below.
3. **"SDK-blocked; no fork-local surface exists."** False — stock replacement
   provides a fresh factory API; the gap is Remote Pi's module-global
   ownership, not a missing SDK affordance.
4. **TUI/editor injection** (`setEditorText` + Enter, `pasteToEditor`,
   `process.stdin` emit, custom-editor `onSubmit`). Rejected by deep
   investigation: cannot preserve operator drafts, images, literal slash text,
   or steer/follow-up semantics; unsafe under overlays; no-op in RPC mode.
5. **Broadly stabilize the cached `ExtensionAPI` / "latest `AgentSession`"
   pointer.** Unsafe — a global latest-pointer routes to a disposed child
   (reproduced). Do not use.
6. **Host-class `AgentSession.bindExtensions` shim to capture
   `ReplacedSessionContext`.** Technically works (proven: a wrapped
   `bindExtensions` yields a working `sendUserMessage` on every `session_start`
   including after `/new`), but it observes children too (recreating the
   ownership-selection problem), misses `/reload` (which bypasses
   `bindExtensions`), and is version-sensitive. **Fallback only, not the
   first fix.**

## Target architecture: runtime ownership coordinator

Introduce a process-scoped **`RemotePiRuntimeCoordinator`** with tokenized
owner/satellite semantics. This is the clean lifecycle boundary Remote Pi has
been missing.

### State model

```
UNOWNED
  → CANDIDATE(factory token)
  → ACTIVE(owner token, session id, api)

ACTIVE
  → REPLACING(owner token, expected reason, pending ingress)
  → ACTIVE(new owner token, new session id, fresh api)   # successor claims

ACTIVE
  → DISPOSED   # on quit
```

### Ownership rules

Each factory invocation receives:

- a unique opaque **token** (factory-local);
- its own factory-local `pi`;
- **no immediate authority** over module-global ingress.

Only the **active owner** may:

- publish `messageApi` / bind `SdkSessionProjection`;
- mutate parent session/context/projection/transcript state;
- start or stop relay/mesh/owner resources;
- drain the pending-delivery queue;
- clear bindings on shutdown.

Every destructive operation validates the **exact lease token**. A child or
stale predecessor can never clear a newer owner.

### Normal replacement (`/new`/`/resume`/`/fork`/`/reload`)

1. Parent receives `session_shutdown(reason)`.
2. Coordinator enters `REPLACING`; inbound messages stay pending (existing
   bounded queue).
3. Stock Pi invokes the factory with a fresh API.
4. The fresh factory's `session_start(reason)` claims the successor lease.
5. Coordinator publishes the fresh API; drains pending delivery **exactly once**.

No `withSession` workaround is needed — stock replacement provides the fresh API.

### Child sessions (the actual bug)

While an owner is `ACTIVE`, every additional factory is a **satellite** and
cannot publish process-global state. The child factory runs (tools/commands
register), but `bindApi`/`bindSessionContext`/relay-start are no-ops for it.

**Child detection** — layered:

1. **Primary:** subscribe to `pi.events` for `subagents:child:spawning` and
   `subagents:child:session-created` (emitted by `@gotgenes/pi-subagents`
   synchronously, immediately before child `bindExtensions()` —
   `child-lifecycle.ts:23,37`). Record child session IDs in the coordinator.
   Deny ownership when a child's `session_start` arrives whose session ID is
   in that set.
2. **Fallback:** the existing `subagentGate.isActive()` (tool-execution window)
   remains as supporting evidence for content suppression, but is **not** the
   ownership authority — delayed/background children can initialize outside the
   parent tool-execution window.
3. **Generic guard:** even for unknown child providers, deny a candidate while
   a live owner already exists (fail closed).

`subagents:child:disposed` clears the child session ID from the registry.

### Reload-safe coordinator storage

Store the coordinator under a versioned global symbol so it survives cached
factory reuse or module re-evaluation:

```ts
globalThis[Symbol.for("remote-pi.runtime-coordinator.v1")]
```

with explicit schema/version checking on retrieval.

## Delivery design boundary (the clean split)

Longer term, split the current singleton:

**Process-scoped (coordinator-owned):**
- relay connection; owner channels; bounded ingress queue; runtime ownership
  generation; pairing + stable room identity.

**Factory/session-scoped (per-owner):**
- `SdkSessionProjection`; session/command contexts; session-id issuer;
  transcript/turn projection; lifecycle subscriptions.

A subagent may have its own session projection — or none — but cannot overwrite
the phone-facing owner.

## Minimal safe implementation slice

1. Introduce `RemotePiRuntimeCoordinator` + opaque factory lease tokens.
2. Stop binding `pi` directly during factory construction; publish the
   factory-local API only after an ownership-approved `session_start`.
3. Make `session_shutdown` / `clearStaleContexts` / relay teardown
   **token-checked** (only the matching owner clears).
4. Deny child + duplicate factory ownership (layered detection above).
5. Preserve the existing pending-delivery queue through `REPLACING`.
6. Align the compile dependency/lockfile with host Pi **0.80.6** (currently
   `^0.79.10` in `pi-extension/package.json`; the running `pi` is 0.80.6).
7. Remove the spike logging handlers (see below) after real tests pass.

A one-line `if (subagentGate.isActive()) return` would mask the common case
but is **not robust enough** for background children or replacement races. Do
not ship that alone.

## Mandatory non-mock integration tests

Mocks cannot model the runtime-staleness or the child-factory collision (the
lesson from the reverted first fix). The suite must use the **real host
loader/runtime**:

1. **Stock `/new` replacement** — fresh factory API created; phone-style message
   reaches the replacement parent exactly once.
2. **Live child while parent idle** — child factory cannot replace parent
   ingress; phone message reaches parent, never child.
3. **After child disposal** — parent delivery still works; no stale/null
   transition.
4. **Four parallel children** — out-of-order start/disposal cannot change the
   owner token or API.
5. **Child during replacement gap** — child cannot claim the reserved successor
   lease; real successor claims and drains queued ingress once.
6. **Stale teardown** — an old or satellite factory cannot clear the current
   binding, relay, or queue.
7. **Duplicate `session_start(new)`** — RPC currently emits it twice;
   activation + queue drain must be idempotent.

## Spike artifact (committed, to be removed)

Commit `d554f13` shipped a **logging-only** `session_before_switch` +
`session_before_fork` handler in `pi-extension/src/index.ts` (+
`_spikeLogSessionBeforeSwitch` helper) and a throwaway script
`pi-extension/spike-session-before-switch.mjs` (gitignored). The spike
disproved the cancel-and-re-drive (rejected alternative #2). The logging
handlers can stay until the real integration tests confirm the live payload,
then **remove both**.

## What IS fixed and deployed (not this story)

- `delivery_pending` tolerance + bounded replay queue + app-side timer disarm
  — `story-stale-ctx-recoverable-delivery-tolerance` (done). Correct mitigation;
  kept.
- `resolveRemoteSessionId` / `wrapActionCtx` stale-getter crash guards — done,
  kept.
- Resume transcript backfill — done, kept.

## References

- `pi-extension/src/index.ts` — factory (`:1273`), module globals (`_pi`,
  `_messageApi`, `_sdkSessionProjection`), `bindApi` port (`:1669-1673`),
  `bindSessionContext`/`clearStaleContexts` ports (`:1676-1700`).
- `pi-extension/src/extension/composition_root.ts` — `registerLifecycleHooks`,
  `disposeRuntimePorts`, epoch.
- `pi-extension/src/session/sdk_session_projection.ts` — `bindApi`,
  `bindSessionContext`, `messageApi`, `forget`, `clearStaleContexts`.
- `pi-extension/src/session/subagent_gate.ts` — `SubagentGate` (content
  suppression; not ownership authority).
- SDK host (0.80.6): `dist/core/extensions/runner.js:522` (`emit`→
  `createContext`), `dist/core/agent-session-runtime.js:117-122`
  (`finishSessionReplacement`/`withSession`), `dist/main.js:489-501`
  (replacement runtime factory).
- `@gotgenes/pi-subagents` v18.0.1: `src/lifecycle/create-subagent-session.ts`
  (child factory + `bindExtensions`), `src/lifecycle/child-lifecycle.ts`
  (`subagents:child:*` event channels).
- Live evidence: `~/.pi/remote/debug/delivery.log` (2026-07-10/11).

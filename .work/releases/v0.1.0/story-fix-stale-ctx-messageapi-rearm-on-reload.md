---
id: story-fix-stale-ctx-messageapi-rearm-on-reload
kind: story
stage: done
tags: [pi-extension, bug, lifecycle]
parent: epic-remote-session-resilience-refactor
feature_parent: feature-session-stable-message-delivery
depends_on: []
release_binding: v0.1.0
gate_origin: null
created: 2026-07-03
updated: 2026-07-11
reverted_misguided_fix: 2026-07-03
spike_committed: 2026-07-11
---

# Stale `messageApi` after session replacement — runtime ownership coordinator

## Status: implemented; awaiting review.

## Known environment flake (NOT a regression — do not re-investigate)

The test `a second same-name agent joins as <name>#2 instead of being refused`
in `src/extension.test.ts` (~line 4729) fails on `acquireCwdLock` on this dev
VM sandbox. Root cause is environmental, not code: `~/.pi/remote/locks/` is
mounted **read-only** (`EROFS`) in this sandbox, so the UDS `server.listen()`
bind always fails and stale `.sock` files from prior runs cannot be cleaned.
Verified: the failure reproduces identically on the baseline commit `415056d`
(before this story's changes) and via a direct `acquireCwdLock(...)` probe
independent of the test. It is unrelated to message delivery or the
coordinator. Run-to-run variance in *how many* mesh-acquisition tests trip
the same read-only `~/.pi/remote/` state explains why a review pass may see 1–4
such failures. Redirect with `REMOTE_PI_HOME` to a writable dir to exercise
the real lock path; the default sandbox path cannot bind.

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
   redesign" in prior revisions). **Disproven by spike (commit `f1bcbcb`):**
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

Commit `f1bcbcb` shipped a **logging-only** `session_before_switch` +
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

## Implementation notes

- Added `src/extension/runtime_coordinator.ts`: a schema-versioned process-global coordinator under `Symbol.for("remote-pi.runtime-coordinator.v1")`, opaque factory leases, owner/satellite transitions, token-checked shutdown, and synchronous `subagents:child:session-created` / `disposed` tracking.
- Reworked `src/extension/composition_root.ts` so factory construction no longer publishes `ExtensionAPI`. An ownership-approved `session_start` now binds the API/context and drains ingress; duplicate starts are idempotent; only the exact owner lease can clear contexts or tear down relay/mesh resources.
- Wrapped `src/index.ts` ordinary event and command callbacks with owner checks. Replacement shutdown preserves the bounded pending-delivery queue; terminal quit fails it. The existing additive `SdkSessionProjection.bindApi` / pair-code `sendPiMessage` behavior is unchanged once ownership is active.
- Removed the logging-only `session_before_switch` / `session_before_fork` spike handlers and helper. The gitignored throwaway spike script was removed from the working copy.
- Added seven mandatory tests in `src/session/runtime_coordinator.integration.test.ts`. They load the factory through the installed Pi 0.80.6 loader implementation, use real `createExtensionRuntime`, `ExtensionRunner`, and `SessionManager` instances, and exercise the real `runtime.assertActive()` stale-API guard. The only loader bypass is filesystem resource discovery: the factory is supplied inline. Relay/queue ports are deterministic harness adapters; coordinator activation and SDK APIs are not mocked.
- Updated the existing real-SDK replacement harness to reset only the versioned process-global coordinator between isolated Vitest harnesses. Updated broad legacy unit fixtures with an explicit isolated-factory test seam; production APIs always use the real event bus path.
- Aligned `@earendil-works/pi-coding-agent` manifest, lockfile, installed dependency, and stack reference to 0.80.6. No wire shape or protocol metadata changed.

Verification (2026-07-11):

- `corepack pnpm typecheck`: clean.
- `corepack pnpm exec vitest run src/session/runtime_coordinator.integration.test.ts`: 7/7 passed.
- `corepack pnpm test`: 820 passed, 1 failed, 3 skipped. The sole failure is the documented pre-existing `acquireCwdLock` `/tmp` contention in `a second same-name agent joins as <name>#2 instead of being refused`; there are no new failures. An isolation retry was attempted twice, but the same external socket contention remained active on this VM, so the expected isolation pass could not be reproduced in this run.
- `corepack pnpm build`: clean (`dist/` rebuilt locally and remains ignored).

## Implementation notes (review fixes)

- Removed `subagentGate.isActive()` from runtime ownership entirely: coordinator activation now derives authority only from the child-session registry, lease disposition, and live-owner guard. Removed the ownership-fallback method from the session port, legacy adapter, and `index.ts` wiring while retaining the gate's content-suppression uses.
- Added a regression with a real active `SubagentGate` window and a separately registered child session ID; a legitimate replacement session still claims ownership and drains pending ingress.
- Split lifecycle evidence honestly: coordinator/child authority remains covered with the real SDK loader, `ExtensionRunner`, runtime staleness guard, and EventBus contract; replacement-gap, duplicate-start, and stale-predecessor teardown now also run through `SdkSessionReplacementHarness`, the real `src/index.js` factory, `AgentSessionRuntime`, and production `_pendingDeliveryQueue`. No `@gotgenes/pi-subagents` dependency or private child-session graph was added.
- Production-queue assertions prove `delivery_pending` (never premature `internal_error`), queue survival across non-terminal replacement and stale teardown, exact-once successor delivery, and idempotent duplicate `session_start(new)` drain.
- Review-fix verification (2026-07-11): direct `tsc --noEmit` clean; focused integration suite 11/11 passed; full direct Vitest run 821 passed, 4 failed, 3 skipped, with all four failures in the documented read-only cwd-lock/mesh-acquisition cluster in `src/extension.test.ts` and no new failures; direct `tsc` build clean.
- Residual gate-binding fix: removed the last production `subagentGate` ownership decision from `index.ts`'s `bindSessionContext` port. Coordinator-approved owners now always capture `_lastEventCtx`, projection issuer/backfill state, remote session id, and room metadata even when a subagent content-suppression window is open. The composition root returns immediately on denied child activation, so real children never reach this port; the projection's optional `subagentChild` suppression remains available only to explicit projection callers/tests and is dead on the production composition path.
- Added a real-production-port replacement regression in `src/session/runtime_coordinator.integration.test.ts` that holds the production module's gate open across `AgentSessionRuntime.newSession()` and proves the captured remote session id advances to the successor. Updated the obsolete isolated legacy test to assert the gate's content-only role; real child denial remains covered by coordinator integration tests.
- Residual-fix verification (2026-07-11): direct `tsc --noEmit` clean; focused coordinator integration suite 12/12 passed; extension + composition-root suite 192 passed with only the documented cwd-lock environment failure; full direct Vitest run 825 passed, 1 documented cwd-lock failure, 3 skipped; direct `tsc` build clean.

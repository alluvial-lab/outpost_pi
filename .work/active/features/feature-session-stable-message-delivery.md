---
id: feature-session-stable-message-delivery
kind: feature
stage: review
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on:
  - story-fix-stale-ctx-messageapi-rearm-on-reload
release_binding: null
gate_origin: null
created: 2026-07-03
updated: 2026-07-11
designed: 2026-07-11
---

# Session-stable message delivery (the stale-`internal_error` architectural gap)

## Brief

Inbound phone messages are delivered to the Pi agent via `messageApi`
(`wakeAgent` → `sendUserMessage`). After a session replacement the phone gets
`internal_error: Agent rejected incoming message: …ctx is stale…`, then
`agent session not bound yet`, and is broken until a full pi restart — which a
phone-only operator cannot trigger (see parked
`idea-mobile-restart-pi-session-affordance`).

This feature closes the gap: **there must be a reliable way to deliver a user
message to the current live session, surviving session replacement.**

## Corrected root cause (2026-07-11, verified)

The prior "SDK-blocked / no session-stable entry point exists" framing was
**disproven** by real-SDK `/new` probes (both host 0.80.6 and local 0.79.10),
the live delivery log, and four parallel deep investigations. Stock Pi
replacement **does** invoke the extension factory with a fresh, working
`ExtensionAPI` — the gap is not a missing SDK affordance.

The actual defect is a **Remote Pi lifecycle ownership bug**: delivery state
is stored as process-global module singletons, and **in-process child
`AgentSession` factories** (notably `@gotgenes/pi-subagents`) overwrite the
parent's `messageApi` binding. When the child is disposed, the stored child
API goes stale and nothing re-arms the (still-healthy) parent binding.

## Realization

The fix is a process-scoped **`RemotePiRuntimeCoordinator`** with tokenized
owner/satellite semantics: only the active owner may publish `messageApi` /
bind the projection / mutate parent state / start-stop relay; child and
duplicate factories are satellites that cannot. Stock replacement transitions
the owner lease; the fresh factory API re-arms without `withSession`.

Full design, rejected alternatives, and mandatory non-mock integration tests
live in the child story:
`story-fix-stale-ctx-messageapi-rearm-on-reload`.

## Why this is a feature, not a story

The bug class **cannot be validated with mock-based unit tests** — mocks don't
model `runtime.assertActive()` staleness or the child-factory collision (the
lesson from the reverted first fix). The coordinator design is the
load-bearing decision; the implementation is a single stride under it.

## Rejected alternatives (do not re-litigate)

These were investigated and disproven 2026-07-11; see the child story for full
evidence:

- **"Re-arm from the factory `pi`"** (the reverted first fix) — the factory
  `pi` IS re-armed fresh by stock replacement, but a child factory overwrites
  it first; mocks passed, live failed.
- **"Cancel-and-re-drive via `session_before_switch`"** — the event ctx is
  built by `createContext()`, not `createCommandContext()`; it has no
  `newSession`/`fork`/`switchSession`/`navigateTree`/`reload`.
- **"SDK-blocked; no fork-local surface exists"** — false; stock replacement
  provides a fresh factory API.
- **TUI/editor injection** (`setEditorText`+Enter, `pasteToEditor`,
  `process.stdin` emit, custom-editor `onSubmit`) — unsafe: cannot preserve
  operator drafts, images, literal slash text, or steer/follow-up; no-op in
  RPC mode.
- **Broadly stabilize the cached `ExtensionAPI` / "latest `AgentSession`"
  pointer** — routes to a disposed child (reproduced).
- **Host-class `AgentSession.bindExtensions` shim** to capture
  `ReplacedSessionContext` — fallback only (observes children too, misses
  `/reload`, version-sensitive).

## What must ship with the fix

- **A real integration test** against the installed host SDK that drives an
  actual session replacement (and an actual child `AgentSession`) and asserts
  delivery reaches the correct (parent) session, never a disposed child.
  Mock-based tests cannot model `runtime.assertActive()` staleness or the
  child-factory collision — the non-negotiable gate.
- **Clear gap-window semantics:** between a replacement and the rebind, an
  inbound message is queued and delivered exactly once to the new session —
  never a permanent `internal_error` that strands the phone.
- **No regression** to the pair-code QR / `sendPiMessage` path (the additive-
  bind contract in `sdk_session_projection.ts:148-167` must hold).

## Out of scope (tracked separately)

- The mobile restart affordance (`idea-mobile-restart-pi-session-affordance`)
  — adjacent UX concern, separate.
- Crash-class siblings (`resolveRemoteSessionId`, `wrapActionCtx`) — already
  fixed and deployed; unguarded getter reads, a different problem.

## Implementation summary (2026-07-11)

All children are terminal-or-review:

- `story-fix-stale-ctx-messageapi-rearm-on-reload` — **done**. The
  `RemotePiRuntimeCoordinator` closes the root cause: child `AgentSession`
  factories can no longer overwrite the parent's `messageApi`; a legitimate
  successor re-arms even during a subagent tool window; queued ingress drains
  exactly once. 12 real-SDK integration tests + 3 production-queue tests.
  Cross-model reviewed (3 passes: block → fix → block → fix → approve).
- `story-foreign-session-user-message-tolerance` — **review**. App-side
  convergence: the cross-pi duplicate case is already filtered by the app's
  inbound `SessionGate`; the narrow metadata-rebind race is closed by
  suppressing accepted `session_mismatch` as a control signal + arming the
  deferred-sync latch on canonical room-metadata rotation. 3 regression tests.
- `story-stale-ctx-recoverable-delivery-tolerance` — **done** (deployed
  mitigation; kept).
- `feature-session-stable-message-delivery-stale-wake-tolerance` — **done**
  (same-session stale-wake tolerance; kept).
- `story-evidence-stale-ctx-repro-2026-07-09` — **done** (evidence capture,
  superseded by the verified root-cause correction).

Verification: pi-extension typecheck/test/build clean (825 pass / 1 documented
read-only-FS cwd-lock env flake / 3 skip); app `flutter analyze` clean + 80/80
sync tests pass. No wire-shape or protocol-metadata change from the
coordinator; the foreign-session fix is app-side only (extension/relay
contracts unchanged; `PROTOCOL.md` refined to pin `session_mismatch` semantics).

Feature-review Blocker fix: pending-delivery TTL expiry now renews only while
the process-scoped coordinator is `REPLACING`, so slow successor startup cannot
strand the phone with `internal_error`. The original 5-second failure threshold
still applies to broken bindings outside replacement; terminal quit still
fails the bounded queue explicitly. Fix verification: coordinator integration
14/14; full pi-extension suite 827 passed / 1 documented cwd-lock environment
flake / 3 skipped; typecheck and build clean.

## References

- Child story (full design + tests): `story-fix-stale-ctx-messageapi-rearm-on-reload`.
- `pi-extension/src/index.ts` — module globals (`_pi`, `_messageApi`,
  `_sdkSessionProjection`), factory (`:1273`), ports (`:1669-1700`).
- `pi-extension/src/extension/composition_root.ts` — lifecycle hooks, epoch.
- `pi-extension/src/session/sdk_session_projection.ts` — `bindApi`,
  `bindSessionContext`, `messageApi`, `forget`, `clearStaleContexts`.
- `pi-extension/src/session/subagent_gate.ts` — content suppression (not
  ownership authority).
- SDK host 0.80.6: `dist/core/extensions/runner.js:522` (`emit`→
  `createContext`), `dist/main.js:489-501` (replacement runtime factory).
- `@gotgenes/pi-subagents` v18.0.1: `src/lifecycle/create-subagent-session.ts`,
  `src/lifecycle/child-lifecycle.ts` (`subagents:child:*` events).
- Skill: `.agents/skills/pi-extension-typescript/SKILL.md` (stale-context rules).

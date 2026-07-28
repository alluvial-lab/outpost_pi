---
id: story-fix-working-flag-stuck-after-session-shutdown
kind: story
stage: done
tags: [bug, pi-extension, lifecycle]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-28
updated: 2026-07-28
---

# App's working indicator stuck true after a session shutdown during an active turn

## Symptom
The operator observed the mobile app showing the Pi as "working" while the Pi
was actually idle. Relay logs for the paired room show `room_meta_update
fields=["working"]` (working=true) at turn start but NO subsequent
`room_meta_update` carrying `working=false` when the turn ended — the
`working=false` frame was never sent, so the app never converged idle.

## Root cause
`registerLifecycleHooks` in `pi-extension/src/extension/composition_root.ts`
handles the SDK `session_shutdown` event by calling `beginShutdown` then
`disposeRuntimePorts`, which calls `ports.session.clearStaleContexts` and
`ports.relay.stop()`. It NEVER converges the turn projection or publishes
`working=false` before stopping the relay.

When `session_shutdown` fires while a turn is active (reason `"new"` from a
`/new` replacement, or `"quit"`), the SDK invalidates the old runner and the
old turn's terminal `agent_end`/`turn_end` events are dropped on the stale
runner — they never reach the extension's handlers, so the reducer-owned
`working=true` is never transitioned to `false` and never published. The relay
is then stopped, so even a late publish would be undeliverable. The stuck
`working=true` turn snapshot also persists into the successor session until a
future turn boundary happens to republish.

The relay-close path (`_onRelayClose`) and the `_goIdle` path already do the
right thing (`_applyTurnAndPublish({type:"session_shutdown"});
_resetTurnSnapshot(); _publishWorking(false)`), but the SDK `session_shutdown`
handler in the composition root does not — it bypasses the turn projection
entirely.

## Fix approach
Expose `resetTurnSnapshot()` on `SdkSessionProjectionPort` (already public on
`SdkSessionProjection`, which publishes the working-edge diff true→false via
`publishTurnProjection` when the turn was active). Call
`ports.session.resetTurnSnapshot()` in `disposeRuntimePorts` BEFORE
`ports.relay.stop()` so `working=false` is published while the relay is still
connected, and the turn snapshot is reset to idle for the successor session.

## Regression test
- `pi-extension/src/extension/composition_root.test.ts`: verify
  `session_shutdown` calls `ports.session.resetTurnSnapshot` BEFORE
  `ports.relay.stop` (ordering assertion alongside the existing
  `clearStaleContexts` < `relay.stop` < `closeMesh` ordering).
- `pi-extension/src/session/sdk_session_projection.test.ts`: verify
  `resetTurnSnapshot()` on a projection with an active turn publishes
  `working=false` via `publishRoomMeta` and converges the projection to idle.

## Implementation notes

**Execution capability**: host-session inline fix (bounded, single convergence
path, highest-risk class per testing-integrity.md but small surface — no
subagent delegation needed).

**Files changed**:
- `pi-extension/src/extension/ports.ts` — added `resetTurnSnapshot()` to
  `SdkSessionProjectionPort` with lifecycle doc.
- `pi-extension/src/extension/composition_root.ts` — call
  `ports.session.resetTurnSnapshot()` in `disposeRuntimePorts` BEFORE
  `ports.relay.stop()` so `working=false` publishes while the relay is
  connected.
- `pi-extension/src/index.ts` — bind `resetTurnSnapshot` on the session port
  to `_sdkSessionProjection.resetTurnSnapshot()`.
- `pi-extension/src/session/runtime_coordinator.integration.test.ts` — added
  the new port member to the harness mock.

**Tests added**:
- `composition_root.test.ts`: `owner session_shutdown converges the turn
  projection before stopping the relay` — asserts `resetTurnSnapshot` is
  called once and ordered before `relay.stop`.
- `sdk_session_projection.test.ts`: `resetTurnSnapshot on an active turn
  publishes working=false and converges idle` + the already-idle no-republish
  guard.

**Four-step confirmation**:
1. New tests pass (both fail before fix: composition_root test got 0 calls;
   projection tests pin pre-existing correct behavior).
2. Full suite green: 934 passed | 3 skipped (55 files). No regressions.
3. Typecheck clean (`tsc --noEmit`).
4. Symptom match: the relay log showed no `working=false` after a turn that
   spanned a `session_shutdown(new)` at 14:40:37; the composition root now
   publishes `working=false` via `resetTurnSnapshot` before `relay.stop()`.

**Deploy note**: `dist/` rebuilt; the fix requires a full Pi process restart
(not `/reload`) to load — per AGENTS.md the running process keeps the stale
module.

**Parked for separate consideration**: none. The duplicate `room_meta_update`
pairs observed in the relay log (~300µs apart) are a separate, unexplained
noise issue not bundled here.

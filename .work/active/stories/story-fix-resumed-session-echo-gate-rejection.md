---
id: story-fix-resumed-session-echo-gate-rejection
kind: story
stage: done
review_addressed: 2026-07-05
tags: [app, bug, lifecycle, session-replacement]
parent: feature-reconnect-reproduction
depends_on:
  - story-verify-resumed-session-echo-gate-rejection
release_binding: v0.1.0
gate_origin: null
created: 2026-07-05
updated: 2026-07-05
---

# Fix: resumed-session SessionGate rejects the echo → "not delivered" badge

## Brief (verified root cause)

`story-verify-resumed-session-echo-gate-rejection` CONFIRMED the hypothesis via
static trace: the `user_message` echo (`UserInput` in the generated protocol)
goes through `SessionGate`, and after a `/resume` the app can hold a stale
`_activeRef` (old session id) until a control frame carrying the new
`session_id` propagates. In that window:

1. `sendMessage` arms the optimistic row + no-echo timer against the stale
   session id.
2. The echo arrives for the NEW session id and is rejected by the gate as
   `session_mismatch` (or `active_session_unknown` / `missing_session_id`).
3. The gate rejection returns BEFORE the `UserInput` echo case, so the no-echo
   timer is never disarmed.
4. 20s later, `_onSendTimeout` → `_failPendingSend` → "not delivered" badge.

## The confirmed mechanism (cite the trace)

- The echo goes through the gate: `_onServerMessage` calls
  `_sessionGate.accepts(msg, _activeRef)` at `sync_service.dart:549-560`; a
  rejected echo returns at `:561-576` before the `UserInput` echo case at
  `:634-645`, so the disarm at `:642-645` (`_pendingSendTimers.remove(id)?.cancel()`)
  never runs.
- The race window: `ConnectionManager.activeSessionId`
  (`connection_manager.dart:241-246`) preserves the old session id until a
  `room_announced`/`room_meta_updated` carrying the new `session_id` arrives;
  the 50ms rooms-stream debounce (`connection_manager.dart:157-166`) +
  `sendMessage` not checking the session id (`chat_page.dart:385-414`) means a
  send can be armed against the stale ref.
- The wire `user_message` echo maps to `UserInput` (`protocol.g.dart:648-649`),
  which is session-scoped (`protocol.g.dart:618-621`), so the gate rejects it
  on session mismatch.
- Caveat: a later successful `activate()` to the new session cancels pending
  send timers (`sync_service.dart:166-194`), so the visible 20s badge requires
  the stale ref to survive until timeout. The silent variant (rejected echo,
  lost send, no badge if the timer is later cancelled) is also a bug.

## The fix (gate-tolerant echo disarm)

The echo confirms delivery — it should NOT be subject to the session-scoped
transcript gate the way server-push messages are. The gate is about scoping
which session's transcript events the app accepts (so a stale session's
streaming/done doesn't bleed into the new session); an echo is a per-message
delivery confirmation keyed by `inReplyTo`/`id`, not a transcript event to
accept/reject.

### Fix direction (lock at design time)
- **Gate-tolerant echo disarm (primary):** a `UserInput` echo whose `id` (or
  `inReplyTo`) matches a pending send should disarm the no-echo timer BEFORE,
  or independently of, the session-scoped transcript acceptance. The echo
  confirms delivery regardless of session id.
- **Activate/send guard (secondary, optional):** after a `/resume`, `activate`
  could wait for the canonical `session_id` to propagate before arming sends
  (or `sendMessage` could refuse to send while the room's session id is
  stale-vs-pending). This narrows the race window but doesn't eliminate the
  need for gate-tolerant disarm (an echo could still arrive in the gap).

The fix story should cover BOTH the visible badge (timer fires) and the
silent variant (timer cancelled by a later activate, but the echo was still
rejected and the send was lost) — the gate-tolerant disarm fixes both.

## Acceptance Criteria

- [ ] A `UserInput` echo whose id matches a pending send disarms the no-echo
      timer EVEN IF the gate would reject it on session scope (gate-tolerant
      disarm).
- [ ] The echo's transcript acceptance (whether it's appended to the transcript
      as a confirmed row) REMAINS session-scoped — the fix is to the disarm
      path only, not to the transcript gate (don't weaken the session-scope
      protection for server-push).
- [ ] A regression test: simulate the resume race (stale `_activeRef` when the
      echo arrives for the new session) → assert the timer is disarmed (no
      `msgFailed` with `send_timeout`) AND no "not delivered" badge.
- [ ] The regression test would FAIL under the current code (the echo is
      rejected, timer fires) — verify by mental revert.
- [ ] The ring-log signal (`sessionGate` for the echo + no `msgEcho` + no
      `msgFailed`) is no longer produced for this path; OR if the gate still
      rejects the echo for transcript purposes, the `msgEcho` event fires
      (disarm) and `msgFailed` does not. Decide + document.
- [ ] `flutter analyze` clean; `flutter test` green.

## Implementation notes

- Chosen fix approach: **(b) gate reject path**. `_onServerMessage` still runs `SessionGate` first for transcript acceptance; if the gate rejects a `UserInput` echo, `SyncService` now checks whether the echo id matches an armed pending-send timer. A match cancels that timer and records the normal echo signal. This avoids double-emitting `MsgEchoEvent` on accepted echoes and keeps the special case localized to the only path that previously skipped the disarm.
- Per-file changes:
  - `app/lib/data/sync/sync_service.dart`: added `_disarmGateRejectedUserInputEcho` and `_recordUserInputEcho`; gate-rejected `UserInput` echoes with pending ids now cancel `_pendingSendTimers[id]` and emit `MsgEchoEvent`, then return without appending transcript events. The accepted `UserInput` path uses the shared echo logger and preserves existing transcript-confirm behavior.
  - `app/test/data/debug/debug_capture_routing_test.dart`: extended `_syncHarness` with configurable rooms debounce and added a real `SyncService` regression that sends against a stale active ref, publishes a resumed session id, delivers a new-session `UserInput` echo before the rooms debounce rebind, and asserts timer disarm + no `send_timeout` failure + no transcript confirmation.
  - `app/lib/ui/chat/widgets/input_bar.dart`: added a local `deprecated_member_use` ignore next to the existing Flutter-pin comment for `SizeTransition.axisAlignment`, so `flutter analyze` is clean without changing the pinned-channel behavior.
- Regression test teeth / mental revert: without `_disarmGateRejectedUserInputEcho`, the new test's echo returns from the gate before the accepted `UserInput` case, the 40ms pending timer remains armed, and the later assertion fails because a `MsgFailedEvent(code: send_timeout)` and failed user row appear.
- Ring-log shape after the fix: `sessionGate(messageType: user_input, reason: session_mismatch)` still fires because transcript acceptance remains session-scoped; `msgEcho(id: <pending id>)` now also fires from the disarm path; `msgFailed(id: <pending id>, code: send_timeout)` does not fire.
- Transcript gate was **not** weakened: the rejected echo still returns from the gate path and does not append `UserMessageConfirmed`; the regression asserts the stale optimistic row remains pending rather than becoming confirmed.
- Verification from `app/`:
  - `../.tools/flutter/bin/flutter analyze` → `Analyzing app...` / `No issues found! (ran in 3.9s)`.
  - `../.tools/flutter/bin/flutter test` → `00:24 +662: All tests passed!`.
- Deviations: none for the sync fix. The only adjacent cleanup was the analyzer suppression for the already-documented Flutter-pin deprecation in `input_bar.dart`; no UI behavior changed.

## Why this is a story, not an inline fix

The fix touches the gate-vs-echo boundary (a subtle correctness area) and has
a design decision: should the echo bypass the gate entirely for disarm, or
should the disarm happen inside the gate's reject path? The transcript
acceptance must remain session-scoped (don't weaken it). The regression test
needs to simulate the resume race (stale `_activeRef`). This needs a design
pass before implementation — but it's a focused fix, not a feature.

## Out of scope

- The activate/send-guard (secondary) — optional, can be a follow-up if the
  gate-tolerant disarm is sufficient.
- The other reconnect-reproduction items (live-repro-only).
- The session-replacement harness (pi-extension-side; this is app-side).

## References

- Parent: `feature-reconnect-reproduction.md` (item
  `idea-mobile-user-message-not-delivered-timeout`).
- Verify story (done): `story-verify-resumed-session-echo-gate-rejection.md`
  (the static trace + confirmed mechanism).
- Backlog: `.work/backlog/idea-mobile-user-message-not-delivered-timeout.md`.
- The code path to fix:
  - `app/lib/data/sync/sync_service.dart:549-576` (gate), `:634-645` (echo case
    + disarm), `:289-311` (no-echo timeout), `:318-325` (`_onSendTimeout`).
  - `app/lib/data/sync/session_gate.dart` — the gate (do NOT weaken the
    session-scope for transcript acceptance).
- The instrumentation that confirmed it (done): `story-app-capture-routing`
  (`session-gate`, `msg-send`, `msg-echo`, `msg-failed` events).
- `.agents/skills/mobile-remote-coding/SKILL.md` — the resume state machine.

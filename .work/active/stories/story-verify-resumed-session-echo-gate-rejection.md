---
id: story-verify-resumed-session-echo-gate-rejection
kind: story
stage: drafting
tags: [app, observability, bug, lifecycle, session-replacement]
parent: feature-reconnect-reproduction
depends_on:
  - feature-cross-side-observability
release_binding: null
gate_origin: null
created: 2026-07-05
updated: 2026-07-05
---

# Verify: resumed-session SessionGate echo rejection → "not delivered" badge

## Brief (the hypothesis to verify)

`idea-mobile-user-message-not-delivered-timeout` reported user messages on the
phone surfacing a "not delivered" badge (the 20s no-echo timeout,
`sync_service.dart:289-311` → `_onSendTimeout` → `_failPendingSend` code
`send_timeout`). The hypothesis (UNCONFIRMED): **after a resumed session
(`/resume`), the `SessionGate` rejects the echo as a `session_mismatch`,
so the no-echo backstop timer fires at 20s → "not delivered" badge.**

## Code investigation (2026-07-05) — the mechanism is plausible

The path that would produce this:

1. A Pi `/resume` rotates the canonical session id. The relay broadcasts a
   `RoomAnnounced`/`room_meta_updated` carrying the new `session_id`.
2. `ConnectionManager.activeSessionId` (`connection_manager.dart:241-245`)
   reads the session id from the live room's `RoomMeta`.
3. `SyncService.activate(epk, roomId)` (`sync_service.dart:159`) resolves
   `_activeRef` via `_resolveActiveRef` (`:144`), which reads
   `_conn.activeSessionId`.
4. If `activate` is called BEFORE the new session id has propagated to the
   room metadata (or the room metadata arrives AFTER the user sends), then
   `_activeRef.sessionId` is stale (the OLD session id, or null).
5. The user sends a message — `sendMessage` (`:209`) reads `_activeRef` at
   send time; if `_activeRef` is stale, the optimistic row is armed with the
   wrong session id, AND the echo (when it arrives for the NEW session) is
   rejected by the gate (`sync_service.dart:560-575`) as `session_mismatch`.
6. The rejected echo never disarms the no-echo timer (`:644`) → 20s later,
   `_onSendTimeout` → `_failPendingSend` → "not delivered" badge.

**The gap is a race between session-id propagation (relay → ConnectionManager
room metadata → `activeSessionId`) and `activate`/`sendMessage` reading it.**
The instrumentation now captures the exact signals to confirm or refute this
on the next live repro — no guesswork needed.

## Scope

This is a **verify-then-decide** story (per the feature's "reproduce with
cross-side instrumentation, attribute, then decide" framing):

### Verify (the attribution pass)
- Confirm the hypothesis using the now-shipped ring-log instrumentation:
  on the next live repro of "not delivered", the app ring log will show:
  - a `session-gate` event with `reason: session_mismatch` (or
    `active_session_unknown` / `missing_session_id`) for the echo of the
    "not delivered" message id, AND
  - the `msg-send` for that id (with the session id it was armed against) vs
    the echo's session id (mismatched), AND
  - the `msg-failed` with `code: send_timeout` 20s later.
  If the ring log shows the gate rejection, the hypothesis is CONFIRMED and
  the root cause is the session-id-propagation race. If it shows the echo was
  ACCEPTED but the timer still fired, the hypothesis is REFUTED and the bug
  is elsewhere (the echo never arrived, or arrived but didn't disarm — a
  different bug).
- A code-level static trace can partially verify NOW: trace whether
  `activate` can be called with a stale `activeSessionId` after a resume,
  and whether `sendMessage` reads `_activeRef` before the new session id
  propagates. If the static trace shows the race is impossible (the
  `RoomAnnounced` always arrives before `activate`), the hypothesis is
  weakened.

### Decide (after verification)
- If CONFIRMED (session-id-propagation race): the fix is to make the echo
  disarm path session-id-tolerant (the echo confirms delivery regardless of
  session id — the gate is about scoping server-push, not validating echoes),
  OR to ensure `activate` waits for the propagated session id before arming
  sends. Routes to a fix story.
- If REFUTED (echo accepted but timer fired): the bug is in the disarm path
  (`:644`) or the echo never arrived (relay/extension dropped it) —
  different fix.
- If the static trace shows the race is impossible: close the hypothesis and
  re-examine on the next repro with a different lens.

## Why this is a story, not an inline fix

The attribution must precede the fix — the hypothesis is UNCONFIRMED, and the
two possible root causes (gate race vs disarm bug vs echo-never-arrived) have
different fixes. Fixing inline without verifying risks the same "wrong fix
that passes its mock-based tests" failure mode this session already hit
(the `factoryApi` re-arm). The ring log makes the next repro deterministic
to attribute; the static trace can pre-narrow it.

## Acceptance Criteria

- [ ] Static trace: determine whether `activate` can read a stale
      `activeSessionId` after a `/resume` (the race is structurally possible
      or not). Document the finding.
- [ ] If the static trace is ambiguous, document the exact ring-log signal
      that will confirm/refute on the next live repro (the `session-gate`
      event for the echo's message id).
- [ ] If CONFIRMED by static trace OR by a repro: open the fix story with
      the specific root cause (gate race / disarm bug / echo-never-arrived)
      and the verified reproduction.
- [ ] If the static trace REFUTES the race: close this hypothesis with the
      reasoning, and re-scope the "not delivered" investigation to the
      disarm/echo-arrival path.
- [ ] No code change in THIS story (verify-then-decide); the fix is a
      separate story once attributed.

## Out of scope

- The fix itself (separate story, post-attribution).
- The relay/extension echo-drop path (would surface as "echo never arrived"
  in the ring log; that's a different attribution if the gate accepted).
- The ~5min recovery latency (separate item).

## References

- Parent: `feature-reconnect-reproduction.md` (item
  `idea-mobile-user-message-not-delivered-timeout`).
- Backlog: `.work/backlog/idea-mobile-user-message-not-delivered-timeout.md`.
- The instrumentation that makes this attributable (done):
  - `story-app-capture-routing` — `session-gate`, `msg-send`, `msg-echo`,
    `msg-failed` events in the ring log.
  - `story-relay-duplicate-auth-supersession-log` — relay-side timing.
- The code path under trace:
  - `app/lib/data/sync/sync_service.dart:144` (`_resolveActiveRef`),
    `:159` (`activate`), `:209` (`sendMessage` reads `_activeRef`),
    `:560-575` (gate), `:644` (echo disarm), `:289-311` (no-echo timeout).
  - `app/lib/data/transport/connection_manager.dart:241-245`
    (`activeSessionId` from room metadata).
  - `app/lib/data/sync/session_gate.dart` — the gate logic
    (`session_mismatch` / `active_session_unknown` / `missing_session_id`).
- `.agents/skills/mobile-remote-coding/SKILL.md` — the reconnect/resume
  state machine this fits into.

## Open questions (resolve during the static trace)

- Does `RoomAnnounced` (carrying the new session id) always arrive before
  `activate` is called after a `/resume`? Or is there a window where
  `activate` reads the stale `activeSessionId`?
- Is `sendMessage`'s read of `_activeRef` at `:209` the only armed session
  id, or does the echo disarm compare against something else?
- Could the gate reject the echo but the disarm STILL happen via a different
  path (making the "not delivered" badge impossible under this hypothesis)?

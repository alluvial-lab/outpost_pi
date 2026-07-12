---
id: story-verify-resumed-session-echo-gate-rejection
kind: story
stage: done
review_addressed: 2026-07-05
tags: [app, observability, bug, lifecycle, session-replacement]
parent: feature-reconnect-reproduction
depends_on:
  - feature-cross-side-observability
release_binding: v0.1.0
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

## Static trace report

### Verdict

`RACE CONFIRMED (structurally possible)`.

The important qualification is that the failing path requires a stale **old**
`_activeRef`, not a null one, and it requires that the session-id rebind does
not arrive/activate before the no-echo timeout. A null `_activeRef` blocks the
send before any optimistic row or timer is armed (`app/lib/data/sync/sync_service.dart:209`,
`:215-218`). A later successful `activate()` to the new session cancels pending
send timers as part of the session switch (`sync_service.dart:166-175`,
`:187-194`), and `_failPendingSend` also no-ops if its captured
`expectedRef` is no longer active (`sync_service.dart:318`, `:337-339`).
So the shortest debounce-only stale window can reject an echo, but it only
produces the visible 20s badge if the stale ref survives until the timeout.

### The echo-vs-gate crux

The echo **does go through `SessionGate`**. `SyncService._onServerMessage` calls
`_sessionGate.accepts(msg, _activeRef)` before the message switch
(`app/lib/data/sync/sync_service.dart:549-560`). If the gate rejects, it logs a
`SessionGateEvent` and returns immediately (`sync_service.dart:561-576`). The
`UserInput` echo case is below that return (`sync_service.dart:634-645`), so a
gate-rejected echo never reaches `[msg-echo]`, `MsgEchoEvent`, or
`_pendingSendTimers.remove(id)?.cancel()` (`sync_service.dart:642-645`).

The wire `user_message` echo is represented as `UserInput`: the generated parser
maps both `user_input` and `user_message` to `UserInput.fromJson`
(`app/lib/protocol/generated/protocol.g.dart:648-649`), while `UserInput.type`
returns `user_input` (`protocol.g.dart:740`). `user_input` and `user_message`
are both session-scoped server types (`protocol.g.dart:618-621`), and
`sessionIdOfServerMessage` extracts the `UserInput.sessionId`
(`protocol.g.dart:1253-1256`). Therefore a resumed-session echo with the new
session id is rejected as `session_mismatch` when `_activeRef.sessionId` still
holds the old id; with no active ref it is rejected as `active_session_unknown`;
and with an empty echo session id it is rejected as `missing_session_id`
(`app/lib/data/sync/session_gate.dart:39-72`).

### The race window

`ConnectionManager.activeSessionId` is derived only from the active peer's live
room metadata: it iterates `roomsFor(epk)` and returns the matching
`RoomInfo.sessionId` for `_activeRoomId` (`app/lib/data/transport/connection_manager.dart:241-246`).
`SyncService._resolveActiveRef` reads that getter and returns null if the room
metadata has no non-empty session id (`app/lib/data/sync/sync_service.dart:144-150`).
`activate()` stores that resolved value directly in `_activeRef`
(`sync_service.dart:159-175`).

The room metadata can be stale during resume. `room_announced` updates
`RoomInfo.sessionId` from the incoming `sessionId`, but preserves the previous
session id if the announce omitted it (`connection_manager.dart:623-660`).
`room_meta_updated` changes the cached session id only when the meta envelope
actually contains `session_id`; otherwise it preserves the current value
(`connection_manager.dart:709-732`). `rooms` snapshots likewise preserve the
old cached session id when a snapshot room omits `session_id`
(`connection_manager.dart:756-765`). Thus after `/resume`, the app can continue
to expose the old id until a control frame carrying the new `session_id` is
processed.

There is also an explicit propagation gap after a new id is processed.
Control frames are handled by `ConnectionManager._watchControl` /
`_onControl` (`connection_manager.dart:568-574`). Room changes only notify
consumers through `_scheduleRoomsEmit()` (`connection_manager.dart:818-819`),
which uses the configured 50ms debounce (`connection_manager.dart:157-166`) and
adds to `_roomsController` later (`connection_manager.dart:835-840`).
`SyncService` learns about room changes only from that `roomsStream` listener
(`sync_service.dart:109-110`) and then calls `activate()` from `_onRoomsChanged`
when the resolved ref differs (`sync_service.dart:535-545`). `ChatViewModel`
uses the same rooms-stream path to refresh binding (`app/lib/ui/chat/viewmodels/chat_viewmodel.dart:68-70`,
`:157-160`).

`sendMessage` is callable in that window. The composer is disabled for not-ready,
offline, revoked, peer-offline, or presence-offline states, but it does not check
`SyncService.activeSessionRef` or compare the current room session id before
submitting (`app/lib/ui/chat/chat_page.dart:385-414`, `:436-438`).
`ChatViewModel.sendMessage` directly delegates to `SyncService.sendMessage`
(`app/lib/ui/chat/viewmodels/chat_viewmodel.dart:286-288`). `SyncService.sendMessage`
reads the current `_activeRef` once at send time (`sync_service.dart:204-214`),
arms the pending-send timer (`sync_service.dart:246`, `:304-311`), and sends the
client `UserMessage` with that captured session id (`sync_service.dart:277-284`).
If `_activeRef` is still the old resumed-away id, the send and timer are bound
to the old ref while the server echo can arrive with the new id and be rejected
by the gate.

A null active ref is not the same failure: `sendMessage` logs a blocked
`MsgSendEvent` and returns before appending an optimistic row or arming a timer
(`sync_service.dart:215-218`).

### Ring-log confirmation signal

If this hypothesis holds on a live repro, the app debug ring should show:

1. `msgSend` for the target id with `blocked:false` (`app/lib/domain/contracts/debug_log.dart:104-121`,
   emitted at `sync_service.dart:267-274`).
2. A nearby `sessionGate` event with `messageType:"user_input"` (the generated
   representation of the `user_message` echo) and `reason:"session_mismatch"`
   or `"active_session_unknown"` / `"missing_session_id"`
   (`debug_log.dart:167-185`, emitted at `sync_service.dart:568-575`).
3. **No** `msgEcho` for that message id (`debug_log.dart:127-137`, normally
   emitted at `sync_service.dart:642-643`).
4. If `_activeRef` has not since rotated to the new session and cancelled/invalidated
   the old timer, a `msgFailed` for the same id with `code:"send_timeout"`
   about 20s later (`debug_log.dart:143-161`, `_onSendTimeout` at
   `sync_service.dart:318-325`, `MsgFailedEvent` at `sync_service.dart:359-365`).

Important instrumentation caveat: the current `SessionGateEvent` does **not**
include the message id or the expected active-session tail; it serializes only
`messageType`, `reason`, and `sessionIdTail` (`debug_log.dart:167-185`). The
console `debugPrint` includes message/active session tails but not the message
id (`sync_service.dart:562-567`). Therefore the cleanest app-only confirmation
is a single-message repro: `msgSend(id=X)` → `sessionGate(messageType=user_input,
reason=session_mismatch|active_session_unknown|missing_session_id)` → no
`msgEcho(id=X)` → `msgFailed(id=X, code=send_timeout)`. With multiple concurrent
sends, use extension/relay logs to correlate the rejected echo's id.

If the race is only the 50ms rooms-stream debounce after new metadata has already
reached `ConnectionManager`, expect `sessionGate` and no `msgEcho`, but then an
immediate rooms rebind may cancel the timer; in that case there may be no
`msgFailed` for the old id.

### Recommendation

Open a fix story. The safest fix direction is gate-tolerant echo disarm: a
`UserInput`/`user_message` echo with a matching client message id should be able
to cancel the no-echo timer before, or independently of, session-scoped transcript
acceptance. Also consider an `activate`/send guard that waits for the current
room's canonical `session_id` after resume before arming sends. The fix story
should explicitly cover the timer-cancel-on-later-activate behavior so the
observable bug and the silent rejected-echo/lost-send variant are both tested.

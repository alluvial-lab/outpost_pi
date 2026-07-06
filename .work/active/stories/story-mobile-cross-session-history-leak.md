---
id: story-mobile-cross-session-history-leak
kind: story
stage: drafting
tags: [app, pi-extension, relay, bug, transport, session]
parent: feature-reconnect-reproduction
depends_on:
  - story-verify-mobile-dup-and-reorder-reconnect-repro
release_binding: null
gate_origin: null
created: 2026-07-06
updated: 2026-07-06
---

# Mobile chat receives `session_history` from non-active Pi sessions (cross-room leak)

## Observed (2026-07-06, ring log `949-11f1-9243-4d82c1bdd26a.bin`)

Operator reports that **skills/ and starmods/ sessions appear as messages in
the mobile chat** — i.e. the phone is rendering transcript content from Pi
sessions that are NOT the active chat session. The ring log confirms: in the
`14:40–14:43` window (active room `7ADky8889NJy`, active session
`...f05f3343`), **3 distinct sessions** replayed through the app's
`_replayHistory` path:

```
replayDedup sessionIds (last 8) in 14:40-14:43 window:
  c12db9c7: 30 events   (14:40:21)
  06c8acbf: 30 events   (spans 07:17 → 14:41)
  f05f3343: 30 events   (the active session)
```

`replayDedup` only fires inside `_replayHistory` (`sync_service.dart:1199`),
which only runs AFTER the session gate accepts the `SessionHistory` frame
(`sync_service.dart:569`, `sync_service.dart:844-846`). So the gate ACCEPTED
`session_history` frames for 3 different sessions — meaning `_activeRef.sessionId`
matched all 3 at some point, OR the gate is being bypassed.

Across the full ring log, **7 distinct sessions** replayed (390+300+90+60+60+
30+30 events). The phone sees a firehose of cross-session transcript content.

## Root cause (HYPOTHESIS — needs static trace to confirm)

The operator runs **multiple Pi processes** (one per cwd: `remote_pi`,
`skills/`, `starmods/`, + a 4th). Each Pi:
- loads the remote-pi extension,
- connects to the relay with the SAME owner epk (`l2X/dUc=`) but a DIFFERENT
  `room_id` (one per cwd: `7ADky8889NJy`, `SF_DCbXsmreE`, `zuMPC-YTtdUD`,
  `k0H-7lFh371e`),
- broadcasts `session_history` / `agent_message` / `agent_chunk` frames to
  attached owners.

The phone subscribes to presence/rooms for the owner epk and sees all 4
rooms. The phone's active room is `7ADky8889NJy`. But the phone's
`hello.room_id` is `'main'` (`ws_transport.dart:250`) — the phone registers
in `room=main`, NOT in the Pi's cwd-room. So the relay routes Pi→phone
envelopes by the Pi's send-target room.

**The leak path (to confirm):** when a Pi (in cwd-room `SF_DCbXsmreE`, say)
broadcasts a `session_history` to the phone, it sends to
`(phone_epk, <phone's room>)`. If the Pi sends to `room=main` (the phone's
registered room), the relay delivers it. The phone's session gate should
reject it (`session_id` mismatch with the active `7ADky` session) — BUT the
`replayDedup` events prove it DIDN'T reject them. Two candidate explanations:

1. **The app is `activate()`-ing to each session as it receives the
   `session_history`**, because `RoomAnnounced`/`PairOk` from sibling rooms
   drives `_activeRef` to those sessions. Then the gate accepts (the active
   ref matches), the replay runs, and the transcript content lands in the
   active chat's box. Need to trace `_learnSessionFromPairOk` +
   `_onControl(RoomAnnounced)` + how `activate()` is called from the UI
   when rooms snapshpt arrives.
2. **The `session_history` frames from sibling Pis carry the phone's
   EXPECTED session_id** (because the extension stamps `session_id` from
   `currentRemoteSessionId()`, and if the phone's `session_sync` request
   echoed the active session, the sibling Pi might echo it back). Less
   likely — `buildSessionHistoryMessage` uses the Pi's OWN session id.

### Why "skills/ and starmods/ sessions" specifically

Those are cwds the operator has open Pi processes in. Each Pi process is a
separate session in a separate room. The phone is rendering their transcript
content because the cross-room `session_history` frames are reaching the
active chat.

## The fix

Depends on the confirmed root cause:

- If (1) — the app must NOT `activate()` to a session just because a
  `RoomAnnounced`/`session_history` from a sibling room arrives while a
  different chat is open. The active room is a USER choice (which chat the
  operator opened); sibling room metadata updates should NOT switch the
  active transcript ref. The gate is correct; the bug is `activate()` being
  driven by non-user events.
- If (2) — the extension must NOT broadcast `session_history` to owners who
  are not in the Pi's own room, OR the relay must NOT deliver cross-room
  Pi→phone frames when the phone is in `main` and the Pi is in a cwd-room.
  This connects to `story-mobile-send-timeout-relay-room-main-mismatch`:
  the phone registering in `room=main` instead of the Pi's cwd-room is the
  root of BOTH the send-timeout AND this leak.

**Likely the same root as the send-timeout story**: the phone's
`hello.room_id = 'main'` (the app's OWN room) is correct for receiving,
but the Pi sends to the phone's room — if the Pi targets `room=main` (the
phone's room), all Pis' broadcasts land on the phone regardless of which
cwd-room the Pi is in. The phone's session gate filters by session_id, so
non-active sessions should be rejected — UNLESS the app is auto-activating
to them.

## Acceptance Criteria

- [ ] Static trace: does `_activeRef` change when a `RoomAnnounced` for a
      SIBLING room arrives while a different chat is open? Cite the path.
- [ ] Static trace: does the extension broadcast `session_history` to ALL
      attached owners, or only those in the Pi's cwd-room? Cite
      `OwnerMultiplexer.broadcast` + `lateAttachTargets`.
- [ ] Confirm via the ring log: do the `c12db9c7` / `06c8acbf` replayDedup
      sessions correlate with `RoomAnnounced` events for non-active rooms?
- [ ] Decide fix path: app-side (don't auto-activate on sibling room
      metadata) vs extension-side (don't broadcast cross-room) vs both.
- [ ] A regression test: a `SessionHistory` for a non-active session is
      rejected by the gate (or never arrives) → no `replayDedup`, no
      transcript mutation.

## Out of scope

- The send-timeout / `room=main` outbound bug — separate story
  (`story-mobile-send-timeout-relay-room-main-mismatch`), likely same root.
- The dup/reorder identity fixes (landed).

## References

- Ring log: `debug/949-11f1-9243-4d82c1bdd26a.bin` — 7 sessions replayed,
  3 in the `14:40-14:43` window alone.
- Relay logs: 4 Pi auths from `l2X/dUc=` in 4 cwd-rooms
  (`7ADky8889NJy`, `SF_DCbXsmreE`, `zuMPC-YTtdUD`, `k0H-7lFh371e`).
- `app/lib/data/sync/sync_service.dart:569` — the session gate;
  `:844-846` — `SessionHistory` → `_replayHistory`;
  `:1199` — `replayDedup` (only fires after gate accepts).
- `app/lib/data/transport/connection_manager.dart:643` — `RoomAnnounced`
  handler; `:1012` — `_learnSessionFromPairOk`.
- `pi-extension/src/extension/owner_multiplexer.ts:450` — `broadcast` (all
  owners, no room filter).
- `pi-extension/src/session/sdk_session_projection.ts:638` —
  `maybeSendLateAttachSessionSync` (late-attach targets).
- `story-mobile-send-timeout-relay-room-main-mismatch` — likely same root
  (phone in `room=main`, Pis in cwd-rooms).

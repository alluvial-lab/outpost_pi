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

## Root cause (CONFIRMED 2026-07-06 via ring-log correlation + static trace)

**The bug is app-side auto-adoption/auto-activation.** The ring log proves the
active session (`_activeRef.sessionId`) changed **5 times in 3 minutes**
(`c12db9c7 → 06c8acbf → f05f3343 → 96bc2b30 → f05f3343`), each preceded by
a sibling Pi's `peer_online` control frame + envelopes. The static trace
confirms the mechanism:

1. **The extension broadcasts cross-room** (no room filter in
   `OwnerMultiplexer.broadcast` — `owner_multiplexer.ts:450-454`). Each Pi
   process (one per cwd) broadcasts `session_history`/`agent_message` to ALL
   attached owners, regardless of which cwd-room the owner is in. So the
   phone receives frames from all 4 Pis.
2. **The app auto-activates to sibling sessions** via `_maybeAdoptLegacyRoom`
   (`connection_manager.dart:1163-1172`): when a `RoomAnnounced`/
   `RoomsSnapshot` for a sibling room arrives and the active peer has no
   persisted room (or the legacy discovery fires), it mutates
   `_activeRoomId = discoveredRoom`. This feeds back into
   `SyncService._onRoomsChanged` (`sync_service.dart:544-554`), which calls
   `activate(epk, _activeRoomId)` — changing `_activeRef` to the sibling
   room's session. Once `_activeRef` matches, the session gate ACCEPTS the
   sibling's `session_history`, and the transcript content leaks into the
   active chat.

### The smoking gun (ring-log evidence)

```
14:40:21.396  ACTIVE SESSION CHANGED TO: c12db9c7   (preceded by peer_online + envelopes)
14:41:41.085  ACTIVE SESSION CHANGED TO: 06c8acbf   (preceded by peer_online + envelopes)
14:41:52.016  ACTIVE SESSION CHANGED TO: f05f3343   (the real active session)
14:43:13.662  ACTIVE SESSION CHANGED TO: 96bc2b30   (preceded by peer_online + envelopes)
14:43:15.871  ACTIVE SESSION CHANGED TO: f05f3343   (back to the real one)
```

Each session change is driven by an inbound `peer_online` from a sibling Pi
reconnecting (its presence pushes), followed by that Pi's `session_history`
broadcast. The app receives these and `_activeRef` flips to the sibling
session, defeating the session gate.

### Why the gate doesn't catch it

The session gate (`session_gate.dart:39-65`) compares
`SessionHistory.sessionId` to `_activeRef.sessionId`. It's correct — but
`_activeRef` is being mutated by the rooms-metadata path
(`_maybeAdoptLegacyRoom` → `_onRoomsChanged` → `activate()`), not by user
action. So the gate accepts because the active ref already flipped to match.

## The fix

**Both fixes are needed**, but the app-side is the acceptance bug (the gate
accepting is what lets the leak through):

1. **App-side (primary, acceptance bug)**: `SyncService._onRoomsChanged`
   must NOT call `activate()` to a sibling room while a chat is open. The
   active room is a USER choice (which chat the operator opened); sibling
   room metadata updates should NOT switch the active transcript ref.
   `_maybeAdoptLegacyRoom` should only fire when there is no explicitly-
   chosen active room (cold boot / first pair), not when a sibling room
   announces while a different chat is open. The gate is correct; the bug
   is `activate()` being driven by non-user room-metadata events.
2. **Extension-side (defense in depth)**: `OwnerMultiplexer.broadcast` should
   filter by room — a Pi in cwd-room `SF_DCbXsmreE` should not broadcast
   `session_history`/`agent_message` to an owner attached in `7ADky8889NJy`.
   This requires the multiplexer to track per-owner room (currently flat
   `channels: Map<peerId, PeerChannelHandle>` with no room dimension,
   `owner_multiplexer.ts:170-176`). This stops the cross-room frames at the
   source, so the app never sees them.

Fix (1) first — it's the acceptance bug and it's app-only. Fix (2) is a
follow-up hardening that requires extension ownership-model changes.

## Acceptance Criteria

- [x] Static trace: does `_activeRef` change when a `RoomAnnounced` for a
      SIBLING room arrives while a different chat is open? **YES** — via
      `_maybeAdoptLegacyRoom` (`connection_manager.dart:1163-1172`) →
      `_onRoomsChanged` (`sync_service.dart:544-554`) → `activate()`.
- [x] Static trace: does the extension broadcast `session_history` to ALL
      attached owners, or only those in the Pi's cwd-room? **ALL** —
      `OwnerMultiplexer.broadcast` (`owner_multiplexer.ts:450-454`) has no
      room filter.
- [x] Confirm via the ring log: do the leaked replayDedup sessions correlate
      with `peer_online`/envelopes for non-active rooms? **YES** — each
      session change is preceded by `peer_online` + envelopes.
- [ ] Decide fix path: app-side (don't auto-activate on sibling room
      metadata) — **DECIDED: app-side primary, extension-side follow-up.**
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

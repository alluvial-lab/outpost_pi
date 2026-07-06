---
id: story-fix-transport-active-room-reestablishment-on-reconnect
kind: story
stage: drafting
tags: [app, bug, lifecycle, transport]
parent: feature-reconnect-reproduction
depends_on:
  - story-verify-mobile-dup-and-reorder-reconnect-repro
release_binding: null
gate_origin: null
created: 2026-07-06
updated: 2026-07-05
---

# Fix: transport active-room re-establishment on reconnect (the reorder bug)

## Brief (verified root cause)

`story-verify-mobile-dup-and-reorder-reconnect-repro` CONFIRMED via static
trace + ring-log correlation that the **message reordering** is a DISTINCT
bug from the duplicate: a transport-room lifecycle defect where
`WsTransport._activeRoom` remains the default `'main'` (or otherwise diverges
from `ConnectionManager._activeRoomId`) during the reconnect window, causing
inbound envelopes targeting the real room to be dropped as `room-mismatch`
and later re-arriving out of order on the next reconnect's replay.

## The confirmed mechanism (cite the trace)

- `WsTransport` demuxes every post-auth frame using `transport._activeRoom`
  (`ws_transport.dart:107-110`). If an envelope has a non-empty `room` but
  `senderRoom != activeRoom`, the demux returns `dropRoomMismatch`
  (`ws_transport.dart:361-375`) and logs `stage: 'room-mismatch'`.
- A fresh `WsTransport` starts with `_activeRoom = 'main'`; only
  `setActiveRoom` changes it (`ws_transport.dart:275-287`).
- On reconnect, `_connect` sets `ConnectionManager._activeRoomId` from
  `peer.roomId` BEFORE connection, but the newly-created transport still has
  its own default `_activeRoom = 'main'` until the manager propagates it
  (`connection_manager.dart:520-545`).
- `_connect` calls `_propagateActiveRoom(_activeRoomId, ch)` AFTER the factory
  returns, before emitting `StatusOnline` + replaying subscriptions
  (`connection_manager.dart:547-562`). `_propagateActiveRoom` is a dynamic
  best-effort call to `setActiveRoom` (`connection_manager.dart:275-285`).
- **The ring log proves the window is real**: the manager-side status logged
  room `7ADky8889NJy` at online/hydrate (`8e5-...bin:244-245`), but the
  immediately-following inbound envelopes with `senderRoom: "7ADky8889NJy"`
  were STILL dropped as `room-mismatch` (`8e5-...bin:251-252`). That
  combination means the transport demux room (`WsTransport._activeRoom`) was
  still `'main'` even though `ConnectionManager._activeRoomId` was correct —
  the propagation hadn't taken effect (or raced) when the envelopes arrived.
- **The `adopt` path is riskier**: `adopt(IChannel, PeerRecord)` emits online,
  starts ping/watchers, and replays subscriptions WITHOUT setting
  `_activeRoomId` from `peer.roomId` and WITHOUT calling
  `_propagateActiveRoom` (`connection_manager.dart:425-451`). Pairing is the
  only direct caller (`pairing_viewmodel.dart:92-101`).

So: 209 `room-mismatch` drops in the repro are envelopes targeting the real
room being dropped because the transport's `_activeRoom` was transiently
`'main'`, then re-arriving on the next reconnect's replay in a different
order → the operator sees reordering.

## The fix

Eliminate the window where `WsTransport._activeRoom` diverges from
`ConnectionManager._activeRoomId` on reconnect/adopt. Options (lock at design):

1. **Propagate before the first frame can arrive**: in `_connect`, call
   `_propagateActiveRoom` synchronously BEFORE the transport starts
   processing inbound frames (currently it's after the factory returns but
   the channel may already be receiving). Confirm the ordering.
2. **Pass `activeRoom` into the factory**: construct `WsTransport` with the
   correct `_activeRoom` from the start (via the factory / `WsTransport.connect`
   param) rather than defaulting to `'main'` and propagating after. This is
   the single-source-of-truth option — the room is known at connection time
   (`peer.roomId`), so the transport should never start with the wrong default.
3. **Fix the `adopt` path**: `adopt` must set `_activeRoomId` from
   `peer.roomId` and call `_propagateActiveRoom` (it currently doesn't).

Prefer (2) + (3): the transport is constructed with the correct room from the
start (no default-then-propagate race), and `adopt` is fixed to match `_connect`.

## Acceptance Criteria

- [ ] A reconnect no longer drops envelopes as `room-mismatch` when the
      `senderRoom` matches the real room (the 209-drop window is eliminated).
- [ ] `WsTransport` is constructed with the correct `activeRoom` (not
      default `'main'`) on reconnect.
- [ ] `adopt` sets `_activeRoomId` from `peer.roomId` and propagates it
      (matches `_connect`).
- [ ] A regression test: simulate a reconnect where envelopes arrive
      immediately after the channel is established → assert they are NOT
      dropped as room-mismatch (would fail under the current default-`'main'`
      behavior).
- [ ] `flutter analyze` clean; `flutter test` green.

## Out of scope

- The duplicate (user-message identity mismatch) — that's the existing
  `story-mobile-assistant-message-duplicated-live-replay` extended to user
  messages (separate fix, same class).
- The relay (it delivered the envelopes correctly; this is app-side transport).

## References

- Parent: `feature-reconnect-reproduction.md`.
- Verify story (done): `story-verify-mobile-dup-and-reorder-reconnect-repro.md`
  (the static trace + ring-log citations).
- Ring-log evidence: `debug/8e5-11f1-9243-4d82c1bdd26a.bin:244-252, 528-570`.
- The code paths:
  - `app/lib/data/transport/ws_transport.dart:107-110, 275-287, 361-375` —
    demux + `_activeRoom` default + `setActiveRoom`.
  - `app/lib/data/transport/connection_manager.dart:275-285, 425-451,
    520-562` — `_propagateActiveRoom`, `adopt`, `_connect`.
  - `app/lib/config/dependencies.dart:247-285` — `PlainPeerChannel` wrapping.
  - `app/lib/data/transport/peer_channel.dart:57-67` — `setActiveRoom` forward.
- `.agents/skills/mobile-remote-coding/SKILL.md` — reconnect state machine.

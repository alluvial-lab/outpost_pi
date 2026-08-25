---
id: story-fix-transport-active-room-reestablishment-on-reconnect
kind: story
stage: done
updated: 2026-07-07
verified_live: 2026-07-08
tags: [app, bug, lifecycle, transport]
parent: feature-reconnect-reproduction
depends_on:
  - story-verify-mobile-dup-and-reorder-reconnect-repro
release_binding: v0.1.0
gate_origin: null
created: 2026-07-06
implemented: 2026-07-06
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

- [x] A reconnect no longer drops envelopes as `room-mismatch` when the
      `senderRoom` matches the real room (the 209-drop window is eliminated).
- [x] `WsTransport` is constructed with the correct `activeRoom` (not
      default `'main'`) on reconnect.
- [x] `adopt` sets `_activeRoomId` from `peer.roomId` and propagates it
      (matches `_connect`).
- [x] A regression test: simulate a reconnect where envelopes arrive
      immediately after the channel is established → assert they are NOT
      dropped as room-mismatch (would fail under the current default-`'main'`
      behavior).
- [x] `flutter analyze` clean; `flutter test` green.

## Implementation (2026-07-06)

Fix shape chosen: **option (2) + option (3)** — construct the transport with
the correct room from the start, and fix `adopt` to mirror `_connect`.

### Changes

- `app/lib/data/transport/ws_transport.dart` — `WsTransport._` and
  `WsTransport.connect` accept an `activeRoom` param (default `'main'`).
  `_activeRoom` is initialized from it in the constructor, so post-auth
  frames are demuxed against the correct room from frame 1 — no
  default-`'main'`-then-propagate race. The `_activeRoom` field is now
  `final`-ish (set once at construction; `setActiveRoom` still changes it
  for runtime room switches via `switchRoom`/`_maybeAdoptLegacyRoom`).
- `app/lib/config/dependencies.dart` — `_productionConnectionFactory`
  passes `activeRoom: peer.roomId ?? 'main'` to `WsTransport.connect`
  (the reconnect path); `_productionPairingTransportFactory` passes
  `activeRoom: qr.roomId ?? 'main'` (the pair path). The `ConnectionFactory`
  typedef is unchanged — the factories read the room from the `peer`/`qr`
  they already receive.
- `app/lib/data/transport/connection_manager.dart` — `adopt` now sets
  `_activeRoomId` from `peer.roomId ?? 'main'`, resets
  `_activeRoomExplicitlySet`, and calls `_propagateActiveRoom` before
  emitting `StatusOnline`, mirroring `_connect`. Production transports are
  already constructed with the right room (so propagate is a no-op there);
  for channels adopted from external flows it guarantees the room is
  correct even if the transport defaulted to `'main'`.

### Tests

- `app/test/data/debug/debug_capture_routing_test.dart` —
  `WsTransport demuxes post-auth frames against the construction
  activeRoom`: connects with `activeRoom: '7ADky8889NJy'`, pushes an
  envelope targeting that room immediately after auth, asserts it
  enqueues (not room-mismatch) and is receivable. **Verified to fail
  under the old default-`'main'`** (the frame is dropped as
  room-mismatch and `receive()` times out) — confirming the test catches
  the bug.
- `app/test/data/transport/connection_manager_test.dart` — new group
  `ConnectionManager adopt binds the active room` with two cases:
  `adopt` with a `peer.roomId` sets `activeRoomId` and propagates to the
  channel; `adopt` with `peer.roomId: null` falls back to `'main'`.
  Uses a new `_RecordingChannel` that records `setActiveRoom` calls
  (`setActiveRoom` is not part of `IChannel`; the manager reaches it via
  dynamic dispatch in `_propagateActiveRoom`).

### Verification

- `flutter analyze` (whole `app/`): clean.
- `flutter test`: green (full suite).
- Regression test confirmed to fail under the reverted fix (envelope
  dropped as room-mismatch), then green with the fix restored.

### Why the ring-log "propagation didn't take effect" is consistent

The ring log showed `connStatus online room=7ADky...` (manager's
`_activeRoomId` correct) immediately followed by `room-mismatch` drops
for `senderRoom=7ADky...`. That is exactly the default-`'main'`-then-
propagate race: the manager set `_activeRoomId` before connect, but the
transport was constructed with the `'main'` default and the relay pushed
envelopes before `_propagateActiveRoom` ran after the factory returned.
Constructing the transport with the real room from `connect` removes the
window entirely — there is no propagation step to race.

## Out of scope

- The duplicate (user-message identity mismatch) — that's the existing
  `story-mobile-assistant-message-duplicated-live-replay` extended to user
  messages (separate fix, same class).
- The relay (it delivered the envelopes correctly; this is app-side transport).

## Deploy urgency (elevated 2026-07-07 — live quantified evidence)

A fresh live repro (ring log `debug/9c1-11f1-8bca-c9ed4620e936.bin`, 05:00–05:06
UTC) quantified the inbound-demux drop rate with the fix **not deployed**:

- **8,640** inbound envelope frames dropped as `stage:room-mismatch`
  (`senderRoom=7ADky8889NJy` ≠ the transport's stuck `_activeRoom='main'`).
- **2,534** frames enqueued (accepted).
- → **~77% drop rate** — the phone is throwing away over three quarters of
  incoming agent output at the demux boundary, because `_activeRoom` is still
  the `'main'` default instead of the Pi's cwd-room `7ADky`.

This is the **inbound twin** of the bug this story fixes: `dispatch_outer` on
the relay rewrites each envelope's `room` to the sender's authenticated room
(`7ADky`), but the phone's `WsTransport` demux compares against `_activeRoom`,
which defaults to `'main'` and is only patched by the (not-yet-deployed)
`connect(activeRoom:)` fix. The 77% figure is the user-visible cost of the
fix not being live — most agent output is silently discarded, which is the
primary driver of the degraded chat experience.

**Action**: rebuild + sideload the app with this fix (`ca555be`, in source,
`stage: review`) and confirm the `room-mismatch` drops fall to zero in a
fresh ring log. This is the deploy step the fix has been waiting on; the live
evidence elevates its priority over the still-open subagent-content leak
(Bug 2 #1), because until the demux stops dropping frames, no agent output —
main or subagent — reaches the phone reliably.

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

## Review (2026-07-08)

**Verdict**: Approve - story verified by implement + verified live on phone; fast-lane advance

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane review. Implementation record shows green verification
(`flutter analyze` clean; `flutter test` green full suite; regression test
confirmed to fail under the reverted fix — envelope dropped as room-mismatch
— then green with the fix restored). Additionally verified **live on the
operator's phone** this session: zero `room-mismatch` drops on the relay
(was 77% pre-fix — 8,640 dropped frames in one capture), correct room
`7ADky8889NJy` on all frames, and sends echo within ~1s (no 20s
`send_timeout`). The `_activeRoom`-stuck-at-`'main'` root cause is closed
for both the inbound demux (this story) and the send path
(`story-mobile-send-timeout-relay-room-main-mismatch`, the send-side twin).

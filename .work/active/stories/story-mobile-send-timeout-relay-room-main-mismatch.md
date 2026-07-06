---
id: story-mobile-send-timeout-relay-room-main-mismatch
kind: story
stage: drafting
tags: [app, pi-extension, relay, bug, transport, lifecycle]
parent: feature-reconnect-reproduction
depends_on:
  - story-verify-mobile-dup-and-reorder-reconnect-repro
  - story-fix-transport-active-room-reestablishment-on-reconnect
release_binding: null
gate_origin: null
created: 2026-07-06
updated: 2026-07-06
---

# Phone user message "not delivered" — relay sees `room=main` while app believes `7ADky...`

## Observed (2026-07-06 clean repro, ring log `949-11f1-9243-4d82c1bdd26a.bin`)

Operator sent a message from the phone at `14:42:47`:

```
3025 msgSend id=cli_019f37e1-... preview="second pass review yes, park the deferred item"
3024 workingConv room=7ADky8889NJy working:true   (mark_room_working)
3028 roomSnapshot room=7ADky8889NJy working:false  (22ms later — working flipped false)
3031 msgFailed id=cli_019f37e1-... code=send_timeout detail="no echo in 20s"
```

No `msgEcho` ever arrived for `cli_019f37e1...`. The phone showed "not
delivered" after the 20s timeout.

The workstation side concurrently logged:

```
[remote-pi] fanout-presence: Pi rejected message: agent session not bound yet
```

## Root cause (CONFIRMED via relay logs + ring log)

**The phone's OUTBOUND envelopes carry `room=main`, not the Pi's real
cwd-room `7ADky8889NJy`.** The relay can't find a Pi registered in
`room=main`, so it drops every envelope with "dest (peer, room) not found":

```
relay WARN: dest (peer, room) not found, dropping from=l2X/dUc= dest=MD/tL3E= room=main bytes=204
```

- `l2X/dUc=` is the Pi's epk tail; `MD/tL3E=` is the phone's epk tail.
  The Pi authenticated in `room=7ADky8889NJy` (relay log
  `02:36:31` + reconnect `03:19:38`), NOT `room=main`.
- The phone's `connStatus` ring-log events report `room=7ADky8889NJy`
  (the manager's `_activeRoomId` is correct), but the relay sees the
  phone's outbound envelopes stamped `room=main` — the `WsTransport`'s
  `_activeRoom` is still the `'main'` default.

### This is the SEND-side twin of the reorder bug

`story-fix-transport-active-room-reestablishment-on-reconnect` fixed the
INBOUND demux race (transport `_activeRoom` defaulting to `'main'` dropped
inbound envelopes as `room-mismatch`). The SEND path has the SAME root:
`WsTransport.send` stamps the outer envelope's `room` field from
`_activeRoom` (`app/lib/data/transport/ws_transport.dart:303-310`), so a
transport stuck at `'main'` sends envelopes the relay can't route.

### Why the fix didn't help this repro

The reorder fix (`80b04e5`) constructs `WsTransport` with
`peer.roomId ?? 'main'` at `connect()` time. BUT:

1. **The fix is not deployed.** These are source commits; the phone is
   running an older APK. The ring log (`14:42`) predates any rebuild +
   sideload. The relay's `room=main` on outbound envelopes is the pre-fix
   behavior.
2. **Even with the fix, the `peer.roomId` may be `null` or stale.** If the
   `PeerRecord.roomId` is null (legacy peer, pre-Plan-17) or the room
   changed since the last pairing, `peer.roomId ?? 'main'` falls back to
   `'main'` and the discovery flow (`_maybeAdoptLegacyRoom`) is relied on
   to patch it. If a send happens before discovery patches, it goes to
   `main`.

### The "agent session not bound yet" is a SEPARATE symptom

The workstation's `[remote-pi] fanout-presence: Pi rejected message: agent
session not bound yet` is the extension's `_sendPiMessage` returning false
because `messageApi` is null (`pi-extension/src/session/sdk_session_projection.ts:522-524`,
`pi-extension/src/index.ts:620-627`). This fires when the extension tries
to inject the `remote-pi:fanout-presence` customType INTO the Pi runtime
(`sendMessage`) but the session isn't bound (startup race / replacement
window). It is NOT the user message being rejected — the user message
never reached the Pi because the relay dropped it at `room=main`.

Two failure layers stacked: the relay dropped the user message (room
mismatch), AND the extension's fanout-presence notification couldn't be
injected (session not bound). The operator sees both.

## The fix

1. **Deploy the reorder fix** (rebuild + sideload the app with `80b04e5`).
   That eliminates the default-`'main'` outbound stamps on reconnect.
2. ** Harden the `peer.roomId == null` path**: when `peer.roomId` is null
   at connect time, the transport should NOT default to sending `'main'`
   outbound — it should either wait for discovery to establish the room
   (queue sends) or send to the room the relay reports via
   `room_announced`/`rooms` snapshot. Currently `peer.roomId ?? 'main'`
   silently sends to `main`, which the relay can't route.
3. **The fanout-presence "session not bound"**: the extension should
   either queue the fanout-presence notification until `messageApi` is
   bound, or drop it silently (it's a best-effort UI hint, not a delivery
   contract). Surfacing it as a `console.error` "Pi rejected message" is
   noisy for a recoverable condition. See
   `story-extension-suspend-fanout-on-peer-offline` (done) for the
   fanout-suspend semantics — this is the notification path, not the
   suspend path.

## Acceptance Criteria

- [ ] Deploy: rebuild + sideload the app with the reorder fix; confirm the
      relay no longer logs `room=main` for the phone's outbound envelopes.
- [ ] Static trace: when `peer.roomId` is null at connect, what does the
      transport send outbound? Cite the path. Decide: queue vs. discovery-wait
      vs. acceptable `'main'` fallback.
- [ ] The fanout-presence "session not bound" error is either silenced for
      the recoverable case or queued until bound.
- [ ] A live repro after the deploy: send a message right after reconnect
      → echo arrives, no `send_timeout`.

## Out of scope

- The dup/reorder identity fixes (separate stories, landed).
- The relay's `dest not found` logging (it's correct — there's no Pi in
  `room=main`).

## References

- Ring log: `debug/949-11f1-9243-4d82c1bdd26a.bin:3023-3031` (the failed
  send + 20s timeout).
- Relay logs: `room=main` on the phone's outbound, `dest not found` drops.
- `app/lib/data/transport/ws_transport.dart:250` — `hello.room_id = 'main'`
  (the app's OWN room, correct).
- `app/lib/data/transport/ws_transport.dart:303-310` — `send` stamps
  `room: _activeRoom` (the DESTINATION room — this is the stuck-`'main'`
  field).
- `story-fix-transport-active-room-reestablishment-on-reconnect` (done,
  stage: review) — the inbound twin of this bug.
- `.work/backlog/idea-mobile-user-message-not-delivered-timeout.md` — the
  original idea (now grounded with a confirmed root cause).

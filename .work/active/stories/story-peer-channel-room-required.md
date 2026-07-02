---
id: story-peer-channel-room-required
kind: story
stage: review
tags: [pi-extension, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-02
updated: 2026-07-02
---

# /remote-pi pair: pairing succeeds but post-pair traffic dropped (relay rejects frame missing `room`)

## Brief

After the cross-room `pair_request` fix (`story-pair-request-cross-room-dropped`),
pairing itself completes — the app shows "Paired with Android device" — but the
session never hydrates: the app spins and shows no chat/transcript. The relay
debug log shows the relay rejecting every frame the Pi sends to the app:

```
WARN invalid relay frame, dropping  peer=YqWjpYw=  err=invalid json: missing field `room` at line 1 column 447
```

(`peer=YqWjpYw=` is the Pi.)

## Reproduction

1. relay-0.2.0 + extension dist with the prior two fixes (QR render + cross-room pair).
2. `/remote-pi pair` renders QR; app scans → "Paired with Android device".
3. App then spins; no chat/transcript hydrates. `docker logs` shows repeated
   `invalid relay frame, dropping … missing field room` for the Pi peer.

## Root cause (verified via relay debug logs + source)

`PlainPeerChannel.send` (`pi-extension/src/transport/peer_channel.ts`) emitted
outbound envelopes as `{ peer, ct }` — **no `room` field**:

```ts
const outer: OuterEnvelope = { peer: this.remotePeerId, ct };
```

This was a deliberate, older defensive decision (the `NOTE: room removed from
the outer envelope until relay (W1.A) + app (W1.C) accept the field` comment,
dating to MVP commit `3587db4`). But relay-0.2.0 introduced a paired wire
change: `relay/src/protocol/generated/outer.rs` now derives

```rust
#[serde(deny_unknown_fields)]
pub struct OuterEnvelope {
    pub peer: String,
    pub room: String,   // REQUIRED, non-optional
    pub ct: String,
}
```

so every `{peer, ct}` frame is rejected at the relay decode boundary with
`invalid json: missing field room` and dropped. The app never receives any
post-pair server→app traffic (no `session_history`, no `agent_chunk`, etc.) →
spinning.

This is the `to_room required (relay-0.2.0 ↔ extension-0.6.0 sender)` paired
wire change flagged in AGENTS.md "Paired wire changes" — the extension sender
side was never updated to match relay-0.2.0.

### What value `room` must carry

The relay's `dispatch_outer` uses `env.room` as the DESTINATION room for
`(peer, room)` routing (`send_to_room(&dest_peer, &dest_room, …)`). The app
always authenticates in `room='main'` (hardcoded `hello.room_id='main'` in
`app/lib/data/transport/ws_transport.dart`), so the app registers at
`(appPubkey, "main")`. Therefore the Pi's outbound `room` must be `"main"` for
the relay to route to the app.

The relay then rewrites the DELIVERED frame's `room` to the SENDER's auth room
(this Pi's cwd-room) for anti-spoof — which the app's inbound filter accepts
(the app sets `activeRoom` to the Pi's room after pairing). So `"main"` is
correct for routing and the rewritten value is correct for the app's filter.

### Why a stale `myRoomId` constructor param existed but was unused

`PlainPeerChannel` had a third constructor param `myRoomId` (the Pi's own room),
added at `0956a74` "for forward-compat" but `void myRoomId`-discarded. It
reflected a misunderstanding: the relay uses `env.room` as the DESTINATION room
(routing), not the sender's room. Emitting `myRoomId` (the Pi's room) would
have routed to `(appPeer, piRoom)` — which doesn't exist — and failed. The
correct destination-room value is the app's auth room (`"main"`).

## Fix

`pi-extension/src/transport/peer_channel.ts`:
- Removed the unused `myRoomId` constructor param (it carried the wrong value
  — the Pi's room, not the app's).
- `send()` now emits `room: APP_DESTINATION_ROOM` (`"main"`, a new module
  constant documented as the canonical app auth room) on every outbound
  envelope, so the relay routes to `(appPeer, "main")`.
- `OuterEnvelope.room` is now required (`string`, not `string?`) matching the
  relay's generated wire type.

`pi-extension/src/extension/relay_transport.ts`: `createPeerChannel` no longer
passes the (wrong) `roomId` to `PlainPeerChannel`.

`pi-extension/src/extension.test.ts` + `src/session/broker_remote.test.ts`:
- Flipped the obsolete `PeerChannel outer envelope omits room field` test to
  assert the new contract (every channel frame carries `room === "main"`).
- Updated `PlainPeerChannel` test constructions (removed the dropped `myRoomId`
  positional arg).

## Verification

- `corepack pnpm typecheck` → clean.
- `corepack pnpm build` → `dist/transport/peer_channel.js` emits
  `room: APP_DESTINATION_ROOM` (verified).
- `corepack pnpm exec vitest run` (full suite) → **722 passed, 3 skipped, 0
  failed** across 45 test files. Includes the flipped room-presence test, the
  cross-room pair regression, and the QR-render regression.

## Operator verification (live)

The fix is in `dist/`. Per AGENTS.md, `/reload` does NOT re-`require`
`dist/index.js` — a **full pi process restart** is required. After restart:
re-pair (the existing peer record may be fine — pair again only if needed), and
the app should hydrate the session/transcript instead of spinning.

## Files

- `pi-extension/src/transport/peer_channel.ts` — `room` emitted + required;
  `APP_DESTINATION_ROOM` constant; `myRoomId` param removed.
- `pi-extension/src/extension/relay_transport.ts` — `createPeerChannel` updated.
- `pi-extension/src/extension.test.ts` — room-presence test flipped.
- `pi-extension/src/session/broker_remote.test.ts` — `PlainPeerChannel`
  constructions updated.

## Context

Third bug in the pairing arc (after `story-pair-code-qr-not-rendering` and
`story-pair-request-cross-room-dropped`). The relay debug log was again
decisive: `invalid json: missing field room` pinpointed the exact missing
field and the peer (the Pi) sending it. This completes the
relay-0.2.0 ↔ extension-0.6.0 paired wire change on the app↔Pi path.

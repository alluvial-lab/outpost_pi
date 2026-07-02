---
id: story-pair-request-cross-room-dropped
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

# /remote-pi pair: app times out — pair_request dropped by recipient-side room guard

## Brief

After the QR-rendering fix (`story-pair-code-qr-not-rendering`), `/remote-pi pair`
renders the QR and the app scans it and connects to the relay, but the app then
shows a spinning wheel for ~30s and fails with
`"Timed out — make sure /remote-pi is running on your Mac"`. The relay shows the
app authenticated, then disconnected 30s later — no `pair_ok` ever returned.

## Reproduction

1. relay-0.2.0 + extension dist with the QR-rendering fix (live).
2. `/remote-pi pair` renders the QR (carries `rm=<pi-cwd-room>`).
3. App scans QR (or pastes the pairing code) → connects to relay.
4. App spins ~30s → `"Timed out — make sure /remote-pi is running on your Mac"`.

## Root cause (verified via relay debug logs + source)

`OwnerMultiplexer.handleOuterLine` (the live ingress path for outer envelopes on
the transport route) had a recipient-side room guard:

```ts
if (outer.room && input.roomId && outer.room !== input.roomId) return;
```

This guard is wrong because of how the relay delivers outer envelopes. In
`relay/src/handlers/connection_actor.rs::dispatch_outer`:

- **Routing** uses the ORIGINAL envelope `room` (`dest_room = env.room`) to look
  up the recipient via `send_to_room(&dest_peer, &dest_room, …)` keyed by
  `(peer_id, room_id)`. The app's envelope carries `room=<pi-cwd-room>` (set via
  `setActiveRoom(qr.roomId)`), so it routes to the Pi correctly.
- **Delivered frame rewrite**: the relay rewrites the delivered envelope's `room`
  to the SENDER's authenticated `room_id` (anti-spoof: "recipient sees sender's
  room_id"). The app authenticates in `room='main'` (always — see
  `app/lib/data/transport/ws_transport.dart`, `hello.room_id = 'main'`), so the
  Pi receives `outer.room = 'main'`.

The Pi's own room is its cwd-room (e.g. `7ADky8889NJy`), so the guard
`'main' !== '7ADky8889NJy'` is **always true** → the `pair_request` is silently
dropped. No `pair_ok` → app times out.

### Relay log evidence

```
14:39:35  authenticated peer=/uV6O0I= room=main  addr=192.168.40.136   ← app
14:40:05  disconnected  peer=/uV6O0I= room=main                       ← 30s timeout
```

No `"dest (peer, room) not found"` warning (routing succeeded) and no envelope
forward logged — the message reached the Pi and was dropped by the guard.
Verified `RUST_LOG=relay=debug,info` was active, so `warn!`-level dest-not-found
would have appeared; its absence confirms the forward succeeded.

### Why the existing suite didn't catch it

The `owner_multiplexer.test.ts` tests always set `room: "room-1"` matching
`roomId: "room-1"` — they never exercise the mismatch case. And
`extension.test.ts`'s `makeInnerLine` helper emits `{peer, ct}` with **no**
`room` field, so the guard (`outer.room && …`) short-circuits false. Both hide
the guard. Same false-green pattern as the QR-rendering bug: test envelope
shapes that don't match what the relay actually delivers.

### Scope: this breaks ALL app→Pi traffic, not just pairing

The app **always** authenticates in `room='main'` (pairing AND normal connect —
`hello.room_id='main'` in `ws_transport.dart`). It uses `setActiveRoom` /
`_activeRoomId` only for the outbound envelope's `room` (routing). The relay
**always** rewrites the delivered `room` to the sender's auth room (`main`). So
the guard would drop every cross-room app→Pi message post-pair too. Pairing
surfaced it first only because it's the first end-to-end test of the cross-room
path.

## Fix

`pi-extension/src/extension/owner_multiplexer.ts` — removed the recipient-side
room guard from `handleOuterLine`. Room routing is already enforced by the
relay's `(peer, room)` lookup; the delivered `outer.room` is the sender's auth
room (anti-spoof), not a destination to re-check. Sender identity is established
by Ed25519 auth at the relay, so removing the guard opens no spoofing surface.

```diff
   async handleOuterLine(input: OwnerOuterLineInput): Promise<void> {
     const outer = decodeOuterEnvelope(input.line);
     if (!outer) return;
     if (!input.isCurrent()) return;
-    if (outer.room && input.roomId && outer.room !== input.roomId) return;
+    // NOTE: do NOT re-check `outer.room` against `input.roomId` here. …
     if (this.channels.has(outer.peer)) return;
```

`input.roomId` is still used downstream (`attach`'s `roomId: input.roomId`).

Note: `PairingCoordinator.handleOuterLine` has the same guard, but that path is
dead code in the live transport route (`_pairingCoordinator.startRelay` is
overridden by `_startRelayViaTransport`, which wires `_owners.handleOuterLine`).
It was left unchanged to keep the diff minimal and honest (no decorative edits to
dead code).

## Test

New regression test in `pi-extension/src/extension.test.ts` plus a
`makeRelayDeliveredLine(peer, senderRoom, inner)` helper that emits the realistic
relay-delivered envelope shape (`{peer, room: <sender auth room>, ct}`). The test
sends a `pair_request` with `room='main'` (the app's auth room, as the relay
rewrites it) against a Pi in its cwd-room and asserts pairing still succeeds
(`pair_ok` returned). Was **1 failed** before the fix, **green** after.

## Verification

- `corepack pnpm exec vitest run src/extension.test.ts` → **170 passed** (the
  previously-flaky 2 `listenerCount` tests also green this run).
- `corepack pnpm exec vitest run src/extension/owner_multiplexer.test.ts` →
  all pass (no test pinned the guard's reject behavior).
- `corepack pnpm typecheck` → clean.
- `corepack pnpm build` → `dist/extension/owner_multiplexer.js` rebuilt with
  the guard removed (verified: `grep -c` for the old guard line = 0).

## Operator verification (live)

The fix is in `dist/`. Per AGENTS.md, `/reload` does NOT re-`require`
`dist/index.js` — a **full pi process restart** is required. After restart,
re-run `/remote-pi pair` and scan with the app: the app should pair (no timeout),
the Pi TUI should show the paired device, and the app should navigate to the
session/chat view.

## Files

- `pi-extension/src/extension/owner_multiplexer.ts` — guard removal + comment.
- `pi-extension/src/extension.test.ts` — `makeRelayDeliveredLine` helper +
  cross-room pair regression test.

## Context

Second bug in the pairing arc (after `story-pair-code-qr-not-rendering`).
Debugging trail in `.work/SESSION-NOTE-2026-07-02-paired-deploy-debugging.md`.
The relay debug log (`RUST_LOG=relay=debug`) was the decisive signal: the absence
of a "dest not found" warning proved the message reached the Pi and was dropped
recipient-side, not lost in routing.

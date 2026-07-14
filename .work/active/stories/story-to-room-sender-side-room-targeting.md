---
id: story-to-room-sender-side-room-targeting
kind: story
stage: drafting
tags: [pi-extension, bug, security]
parent: epic-bold-canonical-session
depends_on: [epic-bold-canonical-session-relay-opaque-targeting]
release_binding: null
gate_origin: null
created: 2026-07-01
updated: 2026-07-13
---

# to_room sender-side room-targeting (cross-PC pi-envelope)

## Brief

The relay half of the `to_room` wire change shipped in relay-0.2.0
(`epic-bold-canonical-session-relay-opaque-targeting`): cross-PC
`pi_envelope` now carries a required `to_room`, the relay routes via
`send_to_room(to_pc, to_room)` (not peer-wide fanout), empty `to_room` →
`bad_envelope`, and `pi_envelope_in` echoes `to_room`.

The **sender half was left as a temporary `"main"` default** (commit
`13701ee`, `broker_remote.ts:357,466,531`). This is broken: each Pi's
MeshNode joins `roomIdFor(cwd, sessionName)` — a real 12-char id, NOT
`"main"` — so a `to_room: "main"` envelope reaches no live sibling room and
the relay returns `transport_error: offline`. Cross-PC mesh delivery is
currently non-functional for any real room.

This story threads the destination sibling's actual room through the three
hardcoded `"main"` call sites in `broker_remote.ts`.

## Root cause

`broker_remote.ts` was given the `sendEnvelopeToPi(toPc, toRoom, env)`
signature but passed a literal `"main"` at all three sites because the
sender had no path to the destination room. The relay correctly rejects
empty/missing `to_room` and returns `offline` for an unknown room — so the
hardcode silently breaks delivery rather than failing loud at the sender.

## Design — leader room announcement + relay room discovery

### Why the original "roster derivation" design is unsound

The story's original design claimed: *"the sibling's leader room =
`roomIdFor(info.cwd, info.name)` for any roster entry `info` of that
sibling."* Three grounded facts refute this:

1. **Multiple relay rooms per PC; only the leader hosts the bridge.** In the
   Pi-extension path, EVERY Pi process with `auto_start_relay:true` connects
   its OWN `RelayClient` to `roomIdFor(cwd, sessionName)` (see
   `_startRelayViaTransport` → `_relayTransport.start({ roomId })`,
   `index.ts:~1900`). But `MeshNode._maybeBridge` returns early unless
   `currentRole()==="leader"` (`mesh_node.ts:~230`), so `attachCrossPcBridge`
   only constructs `PiForwardClient`+`BrokerRemote` on the leader. A
   `pi_envelope_in` delivered to a follower's room has no `PiForwardClient`
   listener → silently dropped. **Cross-PC envelopes MUST target the
   sibling leader's room**, not the target peer's room.

2. **The roster cannot identify the leader.** `broker.localPeerInfos()`
   returns ALL local UDS peers (leader + followers) as `{cwd, name,
   address}` with no leader marker. The sender has no way to pick the
   leader's entry.

3. **`roomIdFor(info.cwd, info.name)` doesn't reproduce the relay room for a
   `#N`-suffixed entry.** The broker's `_uniqueIdentity` stuffs `#N` into
   `conn.name` on collision (`broker.ts:~410`), but the relay room is keyed
   on the CLEAN `_displayName(cwd)` (`index.ts:~1900`). The leader is always
   first-to-register → clean name → derivation happens to match, but any
   follower entry with `#N` derives the wrong room.

The original design's grounding (`mesh_node.ts:210-218`) describes the **MCP
self-managed-relay path** (one MeshNode, one room, one roster entry that IS
the leader), not the Pi-extension path (N Pi processes, N relay rooms,
leader-bridge-only). It works for MCP but is broken for the multi-Pi-per-PC
case that the Pi extension actually runs.

### Corrected design

The sibling leader already knows its own room_id (`_myRoomId`, set in
`_startRelayViaTransport`). Announce it in `peers_update`; the sender caches
and targets it. For the cold-cache bootstrap (neither side knows the other's
room yet), use the relay's existing `rooms_check` control frame (no `to_room`
needed) to discover the sibling's live rooms.

#### Site 2 — `handleIncoming` ACK: thread inbound `to_room` (UNCHANGED)

The relay echoes the destination `to_room` on every `pi_envelope_in` frame
(`relay/src/handlers/pi_forward.rs:194`, confirmed `to_room` = the room the
sender targeted = the receiver's room). This is the cleanest ACK target: the
relay already validated it and it is by construction the sender's live room.

Currently `PiForwardClient._handleLine` emits only `[env, fromPc]`, discarding
`to_room`.

- `PiForwardClientEvents.envelope` → `[env, fromPc, toRoom]`.
- `handleIncoming(env, fromPc, toRoom)` — ACK targets `toRoom`.

#### Sites 1 & 3 — data + control: target the cached `leader_room`

**Wire change (minimal):** add `leader_room?: string` to `PeersUpdateBody`.
The leader includes its own `selfRoomId` (a new `BrokerRemoteOptions` field,
set at construction from `_myRoomId`).

- `_localPeersBody()` includes `leader_room: this.selfRoomId`.
- `_setRemoteCache()` caches `leaderRoom` from the inbound `peers_update`.
- **Site 1** (`tryRouteOutbound`): `sendEnvelopeToPi(siblingPk, cachedLeaderRoom, rewritten)`.
- **Site 3** (`_sendControlEnvelope`): `sendEnvelopeToPi(toPc, cachedLeaderRoom, env)`.

Warm-cache data + control both target the single leader room — no fanout,
no derivation, no `#N` ambiguity. The `roomIdFor` import is NOT needed in
`broker_remote.ts` (the leader sends its actual room_id; the sender echoes
it verbatim).

#### Cold-cache bootstrap — `rooms_check` breaks the mutual deadlock

Both sides need the other's `leader_room` to push `peers_update`, but neither
can send a `pi_envelope` (which requires `to_room`) to ask for it. The relay
already exposes `rooms_check` (`relay/src/handlers/control.rs:133`, generated
type `RelayControlFrameRoomsCheck`) — a relay control frame that returns the
sibling's live `room_id[]` WITHOUT needing a `to_room`.

Bootstrap sequence (cold cache, sibling `pcLabel`):
1. Sender emits `rooms_check { peers: [siblingPubkey] }` via `relay.sendControl`.
2. Relay responds with a `rooms` frame: `{ peer, rooms: [{ room_id, … }] }`.
3. Sender fans out a `peers_request` `pi_envelope` to EACH returned `room_id`.
   Only the leader's room has a `PiForwardClient` → only the leader handles it;
   followers' rooms silently drop. Bounded one-time fanout, control-envelope
   only.
4. The leader responds with `peers_update` (now including `leader_room`).
5. Cache warm → all subsequent sends target the single `leader_room`.

This requires a new listener on the relay `"message"` stream for `rooms`
frames (currently `PiForwardClient` only handles `pi_envelope_in`). Scope it as
a small `RoomDiscovery` helper or extend `PiForwardClient`'s `_handleLine`.

**Why not a well-known control room (original option b)?** That requires the
leader to join a SECOND relay room (a second `RelayClient` connection, since
one WS connection registers exactly one `room_id` via hello). `rooms_check`
reuses the relay's existing room-discovery API with no second connection and
no multi-room join — less lifecycle surface for the same result.

#### Convergence

- Warm cache: every send targets the single `leader_room`. No fanout.
- Cold cache: one `rooms_check` + bounded fanout to discovered rooms, then
  `peers_update` warms the cache. The reannounce timer (2 min) re-warms via
  `leader_room` (now known) — no further `rooms_check` needed.
- ACK timeout on a stale `leader_room` (post-failover, sibling re-elected a
  new leader in a new room): the next `peers_update` push carries the new
  `leader_room`; the sender re-targets. No permanent `offline`.

## Acceptance criteria

- [ ] No `"main"` literal remains as a `toRoom` argument in
  `broker_remote.ts` (Sites 1 & 3 target the cached `leader_room`; Site 2
  threads the inbound `to_room`).
- [ ] `peers_update` carries `leader_room`; the receiver caches it and uses
  it as the `to_room` for both data (Site 1) and control (Site 3) sends.
- [ ] `PiForwardClientEvents.envelope` threads the inbound `to_room`;
  `handleIncoming` uses it as the ACK `to_room` (Site 2).
- [ ] Cold-cache bootstrap uses `rooms_check` to discover the sibling's live
  rooms and fans out `peers_request` to each, then converges to the cached
  `leader_room` once `peers_update` returns. No permanent `offline`.
- [ ] A cross-PC data envelope to a sibling leader in a non-`main` room is
  delivered (relay routes to the cached `leader_room`, not `main`).
- [ ] `broker_remote.test.ts` assertions updated: the existing
  `pi.sendEnvelopeToPi("K_B", "main", …)` sites must assert the cached
  `leader_room` (or threaded `to_room` for the ACK), not `"main"`.
- [ ] New tests: `leader_room` round-trips through `peers_update`; cold-cache
  `rooms_check` path; ACK targets threaded `to_room`.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test`, `corepack pnpm build`
    pass.

## Implementation notes

- `BrokerRemote` gains `selfRoomId` (a `BrokerRemoteOptions` field, set at
  construction from `_myRoomId`). It is NOT derived — the leader already has
  it from `_startRelayViaTransport`. The `roomIdFor` import stays in
  `mesh_node.ts`; `broker_remote.ts` does NOT import it.
- `PeersUpdateBody` gains optional `leader_room?: string`.
- `WirePeerInfo` (the `peers_detailed` roster entry) does NOT gain a
  `leader_room` field — `leader_room` is PC-scoped, not peer-scoped.
- `RelayClient.sendControl` already exists for control frames (`pi_forward`
  uses it indirectly; `room_meta_update` uses it directly). `rooms_check` is
  a relay control frame, not a `pi_envelope`.
- The `rooms` response listener can live in a small `RoomDiscovery` helper
  or extend `PiForwardClient._handleLine` to emit a `rooms` event. Prefer the
  latter to avoid a second relay-message listener competing with the existing
  one.
- Keep the optimistic-send + ACK-timeout contract intact; the fix changes
  *which room* is targeted, not whether a send is attempted.
- `MeshMember` (the `mesh_versions` sibling-discovery blob) does NOT carry a
  room_id (`src/mesh/types.ts`); only the relay's `rooms_check`/`rooms` path
  exposes a peer's live rooms. This is why `rooms_check` is the bootstrap
  primitive, not sibling discovery.
- The `to_room` wire field is already the canonical shape (relay-0.2.0).
  The `leader_room` addition is an extension of `peers_update` — we own the
  wire across relay, schema, and extension, so the change ships by rebuilding
  our own artifacts across all of them.

## Why this is a story, not inline

The handoff note described this as "thread it through," but it is
genuinely design-bearing: the inbound `to_room` is discarded today, and the
sender-side room-targeting has a deeper problem than the original
"roster derivation" design anticipated. The original design is unsound for
the multi-Pi-per-PC case (only the UDS leader hosts the cross-PC bridge, but
the roster can't identify the leader and `#N`-suffixed entries derive the
wrong room). The corrected design announces the leader's own room in
`peers_update` and bootstraps cold-cache delivery via the relay's existing
`rooms_check`/`rooms` discovery API (no `to_room` required, no second relay
connection). Scoping it as a tracked story keeps the release honest and gives
the gates a concrete artifact to verify.

## Verification

From `pi-extension/`:

```bash
corepack pnpm typecheck
corepack pnpm test
corepack pnpm build
```

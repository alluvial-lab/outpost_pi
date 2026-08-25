---
id: story-to-room-sender-side-room-targeting
kind: story
stage: done
tags: [pi-extension, bug, security]
parent: epic-bold-canonical-session
depends_on: [epic-bold-canonical-session-relay-opaque-targeting]
release_binding: v0.1.0
gate_origin: null
created: 2026-07-01
updated: 2026-07-15
---

# to_room sender-side room-targeting (cross-PC pi-envelope)

## Brief

The relay half of the `to_room` wire change shipped in relay-0.2.0
(`epic-bold-canonical-session-relay-opaque-targeting`): cross-PC
`pi_envelope` now carries a required `to_room`, the relay routes via
`send_to_room(to_pc, to_room)` (not peer-wide fanout), empty `to_room` →
`bad_envelope`, and `pi_envelope_in` echoes `to_room`.

The **sender half was left as a temporary `"main"` default** (commit
`e2beaa6`, `broker_remote.ts:357,466,531`). This is broken: each Pi's
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

## Design — relay-authoritative room discovery (Option B)

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

### Wire-stance decision: Option B (relay-authoritative)

Two options were considered for how the sender learns the sibling leader's
room:

- **Option A — `leader_room` bolted on `peers_update`.** The leader announces
  its own `_myRoomId` as a new `leader_room` field in `peers_update`; the
  sender caches + targets it verbatim. Cold-cache bootstrap via `rooms_check`.
  Simpler sender, but adds a peer-announced field that duplicates relay state
  and can drift (a stale `leader_room` survives until the next push, even if
  the relay already knows the room ended).

- **Option B — relay as authoritative room source (CHOSEN).** The sender does
  NOT trust a peer-announced room field. Instead it asks the relay directly:
  `subscribe_rooms { peers: [siblingPubkey] }` for live push updates of the
  sibling's rooms, and `rooms_check { peers: [siblingPubkey] }` for a one-shot
  cold-cache snapshot. The relay is the single source of truth for which rooms
  are live; the sender targets the sibling's live room(s) from relay state.

**Operator chose Option B** (2026-07-14 session). Rationale: the relay already
maintains authoritative room state (`RoomManager`, `RoomMeta`, the
`registry_event_publisher` push path) and already exposes `subscribe_rooms` +
`rooms_check` + `room_announced`/`room_ended`/`room_meta_updated` events.
Option A would duplicate that state into a peer-announced field that can drift
from relay truth; Option B reuses the relay's existing room-discovery API with
no new wire field on `peers_update` and no second source of room truth. The
relay is already the authority for `to_room` validation (it rejects unknown
rooms as `offline`); making it the authority for room *discovery* too keeps one
source of truth.

### Corrected design (Option B)

The relay already exposes everything needed (verified against
`relay/src/handlers/control.rs`, `relay/src/peers/rooms.rs`,
`relay/src/peers/registry_event_publisher.rs`,
`relay/src/protocol/generated/room.rs`):

- `subscribe_rooms { peers: [pubkey] }` → the relay pushes `room_announced`,
  `room_ended`, and `room_meta_updated` frames to the subscriber whenever the
  sibling's rooms change.
- `rooms_check { peers: [pubkey] }` → one-shot response `{ type: "rooms",
  peer, rooms: [RoomMeta] }` listing the sibling's live rooms.
- `RoomMeta` carries `room_id`, `name`, `cwd`, `session_id`, `model`,
  `thinking`, `working`, `started_at` — enough to identify the leader's room.

The sender (leader's `BrokerRemote`) subscribes to each sibling's rooms on
bridge attach and maintains a `siblingRooms: Map<pcPubkey, Set<room_id>>`
cache from the relay push events. Sends target a live room from that cache.

#### Site 2 — `handleIncoming` ACK: thread inbound `to_room` (UNCHANGED from
the original corrected design)

The relay echoes the destination `to_room` on every `pi_envelope_in` frame
(`relay/src/handlers/pi_forward.rs:194`, confirmed `to_room` = the room the
sender targeted = the receiver's room). This is the cleanest ACK target: the
relay already validated it and it is by construction the sender's live room.

Currently `PiForwardClient._handleLine` emits only `[env, fromPc]`, discarding
`to_room`.

- `PiForwardClientEvents.envelope` → `[env, fromPc, toRoom]`.
- `handleIncoming(env, fromPc, toRoom)` — ACK targets `toRoom`.

#### Sites 1 & 3 — data + control: target a sibling live room from the relay cache

The sender no longer hardcodes `"main"` and no longer bolts `leader_room` onto
`peers_update`. Instead it targets a room from `siblingRooms` (populated by
`subscribe_rooms` push events + `rooms_check` bootstrap).

- **Site 1** (`tryRouteOutbound`): `sendEnvelopeToPi(siblingPk, pickRoom(siblingPk), rewritten)`.
- **Site 3** (`_sendControlEnvelope`): `sendEnvelopeToPi(toPc, pickRoom(toPc), env)`.

`pickRoom(pcPubkey)` returns a live room from the cache. If the cache has
exactly one room (the normal warm case), target it. If multiple (the sibling
has follower rooms too), prefer the one whose `RoomMeta` matches the leader
heuristic — but in practice only the leader's room has a `PiForwardClient`
listener, so targeting any live room is safe: follower rooms silently drop
the envelope (no listener), and the leader's room delivers. If the cache is
empty (cold), fall through to the bootstrap path below.

**No `leader_room` field on `PeersUpdateBody`.** `PeersUpdateBody` is
unchanged. The `roomIdFor` import is NOT needed in `broker_remote.ts`.

#### Cold-cache bootstrap — `rooms_check` + bounded fanout

On bridge attach (or when `pickRoom` finds an empty cache for a sibling), the
sender bootstraps via the relay's one-shot `rooms_check`:

1. Sender emits `rooms_check { peers: [siblingPubkey] }` via `relay.sendControl`.
2. Relay responds with `{ type: "rooms", peer, rooms: [RoomMeta, …] }`.
3. Sender populates `siblingRooms` from the response.
4. Sender fans out a `peers_request` `pi_envelope` to EACH returned `room_id`.
   Only the leader's room has a `PiForwardClient` → only the leader handles it;
   followers' rooms silently drop. Bounded one-time fanout, control-envelope
   only.
5. The leader responds with `peers_update` (unchanged shape).
6. `subscribe_rooms` push events keep `siblingRooms` warm thereafter — no
   further `rooms_check` needed unless the subscription lapses (relay
   reconnect).

This requires a new listener for `rooms` / `room_announced` / `room_ended`
frames (currently `PiForwardClient._handleLine` only handles `pi_envelope_in`,
discarding everything else). Scope it by extending `PiForwardClient`'s
`_handleLine` to emit a `rooms` event (and `room_announced`/`room_ended`), or
via a small `RoomDiscovery` helper that shares the relay message stream.
Prefer extending `PiForwardClient` to avoid a second relay-message listener
competing with the existing one.

**Why not a well-known control room?** That requires the leader to join a
SECOND relay room (a second `RelayClient` connection, since one WS connection
registers exactly one `room_id` via hello). `subscribe_rooms` + `rooms_check`
reuse the relay's existing room-discovery API with no second connection and no
multi-room join — less lifecycle surface for the same result.

#### Convergence

- Warm cache: every send targets a live room from `siblingRooms` (kept warm
  by `subscribe_rooms` push events). No fanout.
- Cold cache: one `rooms_check` + bounded fanout to discovered rooms, then
  `subscribe_rooms` keeps the cache warm. The reannounce timer (2 min)
  re-warms via the subscription — no further `rooms_check` needed unless the
  relay WS reconnects.
- ACK timeout on a stale room (post-failover, sibling re-elected a new leader
  in a new room): `room_ended` for the old room + `room_announced` for the
  new room arrive via the subscription; the sender re-targets. No permanent
  `offline`.
- Relay reconnect: re-issue `subscribe_rooms` for all known siblings on
  reconnect (the subscription is per-WS-connection).

## Acceptance criteria

- [ ] No `"main"` literal remains as a `toRoom` argument in
  `broker_remote.ts` (Sites 1 & 3 target a live room from the relay-sourced
  `siblingRooms` cache; Site 2 threads the inbound `to_room`).
- [ ] `BrokerRemote` subscribes to each sibling's rooms via `subscribe_rooms`
  on bridge attach and maintains a `siblingRooms: Map<pcPubkey, Set<room_id>>`
  cache from `room_announced`/`room_ended` push events. Sends target a live
  room from this cache (Sites 1 & 3).
- [ ] `PiForwardClientEvents.envelope` threads the inbound `to_room`;
  `handleIncoming` uses it as the ACK `to_room` (Site 2).
- [ ] Cold-cache bootstrap uses `rooms_check` to discover the sibling's live
  rooms and fans out `peers_request` to each, then `subscribe_rooms` keeps the
  cache warm. No permanent `offline`.
- [ ] `PeersUpdateBody` is unchanged (no `leader_room` field — the relay is
  the authoritative room source, not a peer-announced field).
- [ ] A cross-PC data envelope to a sibling leader in a non-`main` room is
  delivered (relay routes to a live room from the cache, not `main`).
- [ ] `broker_remote.test.ts` assertions updated: the existing
  `pi.sendEnvelopeToPi("K_B", "main", …)` sites must assert a cached live
  room (or threaded `to_room` for the ACK), not `"main"`.
- [ ] New tests: `siblingRooms` cache populates from `room_announced` and
  clears on `room_ended`; cold-cache `rooms_check` path; ACK targets
  threaded `to_room`; `subscribe_rooms` re-issued on relay reconnect.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test`, `corepack pnpm build`
    pass.

## Implementation notes

- `BrokerRemote` gains a `siblingRooms: Map<pcPubkey, Set<room_id>>` cache
  populated from relay push events, NOT a `selfRoomId` field (Option A's
  `selfRoomId`/`leader_room` is dropped — the relay is the room authority).
- `PeersUpdateBody` is unchanged (no `leader_room` field).
- `WirePeerInfo` (the `peers_detailed` roster entry) is unchanged.
- `RelayClient.sendControl` already exists for control frames (`room_meta_update`
  uses it directly at `relay_transport.ts:320`; `subscribe_presence` at
  `index.ts:379`). `subscribe_rooms` and `rooms_check` are relay control frames,
  not `pi_envelope`s — send them via the same `sendControl` path.
- The `rooms` / `room_announced` / `room_ended` response listener extends
  `PiForwardClient._handleLine` to emit new events (currently it only handles
  `pi_envelope_in`, discarding everything else). Prefer this over a second
  relay-message listener competing with the existing one.
- `pickRoom(pcPubkey)`: returns a live room from `siblingRooms`. If multiple,
  any live room is safe (follower rooms silently drop; only the leader's room
  has a `PiForwardClient` listener). If empty, trigger the `rooms_check`
  bootstrap.
- Keep the optimistic-send + ACK-timeout contract intact; the fix changes
  *which room* is targeted, not whether a send is attempted.
- `MeshMember` (the `mesh_versions` sibling-discovery blob) does NOT carry a
  room_id (`src/mesh/types.ts`); only the relay's `rooms_check`/`rooms`/
  `subscribe_rooms` path exposes a peer's live rooms. This is why the relay
  is the bootstrap primitive, not sibling discovery.
- The `to_room` wire field is already the canonical shape (relay-0.2.0).
  Option B adds NO new wire field — it reuses the relay's existing
  `subscribe_rooms`/`rooms_check`/`room_announced`/`room_ended` control
  frames. The change ships as an extension-only edit (no relay, schema, or
  app change needed).
- Relay reconnect handling: `subscribe_rooms` is per-WS-connection, so on
  relay reconnect the bridge must re-issue `subscribe_rooms` for all known
  siblings. The existing relay-transport reconnect path already re-runs
  bridge attach; hook the subscription there.

## Why this is a story, not inline

The handoff note described this as "thread it through," but it is
genuinely design-bearing: the inbound `to_room` is discarded today, and the
sender-side room-targeting has a deeper problem than the original
"roster derivation" design anticipated. The original design is unsound for
the multi-Pi-per-PC case (only the UDS leader hosts the cross-PC bridge, but
the roster can't identify the leader and `#N`-suffixed entries derive the
wrong room). The corrected design (Option B) uses the relay as the
authoritative room source via its existing `subscribe_rooms`/`rooms_check`/
`room_announced`/`room_ended` discovery API — no new wire field, no second
source of room truth, no second relay connection. Scoping it as a tracked
story keeps the release honest and gives the gates a concrete artifact to
verify.

## Verification

From `pi-extension/`:

```bash
corepack pnpm typecheck
corepack pnpm test
corepack pnpm build
```

## Implementation (2026-07-15)

Implemented Option B (relay-authoritative room discovery) across 3 files:
- `pi_forward_client.ts`: threads `to_room` on the `envelope` event (Site 2);
  emits validated `rooms`/`room_announced`/`room_ended` control events;
  exposes `sendRoomControl` for `subscribe_rooms`/`rooms_check`.
- `broker_remote.ts`: `siblingRooms` cache from relay push events; `pickRoom()`
  targets a live room (Sites 1 & 3); cold-cache `rooms_check` bootstrap +
  bounded `peers_request` fanout; `subscribe_rooms` on sibling add; leader
  heuristic (oldest `started_at` first); `detach` removes all new listeners.
- `broker_remote.test.ts`: 41 tests (updated `"main"` assertions + new
  cold-cache/ACK/room-event/bootstrap/convergence tests).

No `leader_room` field on `PeersUpdateBody` (relay is the single room truth).
Extension-only change (no relay/schema/app edit).

### Verification
- `corepack pnpm typecheck` clean.
- `corepack pnpm build` clean.
- `corepack pnpm test`: 835 passed, 3 skipped, 8 failed — the 8 failures are
  the documented pre-existing `acquireCwdLock` EROFS environmental flake
  (read-only `~/.pi/remote/locks/`), unchanged from baseline. `broker_remote.test.ts` 41/41 pass.

Advanced `implementing → review`.

## Review (2026-07-15, standalone-story, bounded inline)

Standalone-story bounded inline review (parent epic `epic-bold-canonical-session`
shipped in v0.6.0; this is the sender-half follow-up to the relay-0.2.0
`to_room` wire change). No independent/cross-model reviewer (standalone-story
lane per review skill).

### Lenses walked
- **No `"main"` literal**: confirmed — all 3 sites target a live room from
  `pickRoom()` or the threaded `toRoom`. ✓
- **`PeersUpdateBody` unchanged**: no `leader_room` field (relay is single
  room truth). ✓
- **Lifecycle**: `detach()` removes all new listeners (`rooms`,
  `room_announced`, `room_ended`); `subscribedRooms`/`pendingRoomChecks`
  cleared on sibling removal. ✓
- **Cold cache safety**: `pickRoom()` returns `undefined` when empty — no
  fabricated room send; ACK-timeout contract holds; `rooms_check` warms
  subsequent sends. ✓
- **ACK threading (Site 2)**: `handleIncoming(env, fromPc, toRoom)` threads
  the relay-validated `to_room` to the ACK. ✓
- **Anti-spoof**: `from_pc` sibling-cache check intact; room event handlers
  check `siblingByPubkey.has(frame.peer)` (don't process unknown peers). ✓
- **Idempotency**: `subscribe_rooms` guarded by `subscribedRooms` set. ✓
- **Leader heuristic**: oldest `started_at` first (leader registers first),
  deterministic tie-break. ✓

### Verification
- typecheck clean; build clean; `broker_remote.test.ts` 41/41 pass.
- 8 pre-existing EROFS failures unchanged from baseline.

### Verdict
Approve. No blockers, no important findings. Advanced `review → done`.

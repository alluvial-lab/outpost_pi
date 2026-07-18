---
id: feature-outbound-buffer-on-peer-offline
kind: feature
stage: implementing
tags: [pi-extension, bug, lifecycle]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-09
updated: 2026-07-18
---

# Outbound buffer for Pi→app frames while the app peer is known offline

## Brief

Today the Pi→app data path is **best-effort, fire-and-forget**. When the
extension's `OwnerMultiplexer.broadcast()` reaches a peer it has marked
offline, it silently skips it (`owner_multiplexer.ts:450`:
`if (this.offlinePeerIds.has(peerId)) continue;`) — the frame is **dropped,
not buffered**. The app only recovers the dropped turn later, opportunistically,
if the user pulls-to-refresh (which fires `session_sync`); nothing auto-backfills.

This is an **asymmetry**: the *inbound* (app→Pi) path already has a bounded
in-memory replay queue (`feature-session-stable-message-delivery`, max 2,
overflow → `internal_error`) that survives a session-replacement window. The
*outbound* path has no equivalent. The result, observed live on 2026-07-09:
the relay logged `dest (peer, room) not found, dropping` for ~18 frames
(`bytes=225460` among them — a full turn) while the app was mid-reconnect, and
the operator's mobile never received that turn until manual refresh.

This feature closes the **known-offline window**: buffer outbound
`ServerMessage`s per offline peer while `markPeerOffline` is active, and flush
them on `markPeerOnline`. It mirrors the inbound queue's bounded-in-memory
contract. It is wire-invariant, relay-invariant, and app-invariant — no
`PROTOCOL.md` change, no relay change, no app change.

## Scope boundary — what this is NOT

- **Not the detection-lag window.** This buffer only helps once the extension
  *knows* the peer is offline (i.e. after a `peer_offline` frame arrives).
  Frames sent *before* `peer_offline` arrives — while the relay already has no
  route but the extension hasn't been told — are still relay-dropped. That
  end-to-end gap (relay-side hold, or app auto-`session_sync` on reconnect) is
  a larger, wire-bearing piece of work, parked as
  `idea-outbound-delivery-detection-lag-window` in the backlog. This feature
  does not attempt it.
- **Not a replacement for `session_sync`.** The buffer is in-memory and lost on
  extension restart. `session_sync` remains the durable catch-up of record;
  this buffer is the *common-case* optimization that makes manual refresh
  unnecessary when the disconnect was observed.
- **Not cross-PC mesh delivery.** This is the app↔pi owner path
  (`APP_DESTINATION_ROOM = "main"`). Cross-PC `agent_send`/`pi_envelope`
  forwarding is a separate path with its own `to_room` targeting concerns
  (see `story-to-room-sender-side-room-targeting`).

## Why a feature, not a story

The change is small in lines but design-bearing:

- **Buffer lifecycle** — where the buffer lives (per-peer on the multiplexer,
  or on the `PeerChannel`), when it allocates/frees, and how it interacts with
  channel `detach`/teardown (a detached channel must not retain a buffer that
  outlives its owner).
- **Bound + overflow** — the inbound queue overflows to `internal_error`
  *because the app is online to see it*. An offline app cannot see an error, so
  the overflow policy must be chosen deliberately (drop-oldest-silently vs
  cap-at-one-turn vs surface-on-reconnect). This is a real semantics decision,
  not a one-liner.
- **Flush ordering** — on `markPeerOnline`, buffered frames must flush in
  original order *before* any live post-resume frame, and must not interleave
  with a concurrent `session_sync` replay (which would duplicate). Ordering
  against the existing `lateAttach` path also needs a decision.
- **Testability** — the multiplexer has unit tests for suspend/resume
  (`owner_multiplexer.test.ts:108`) that currently assert `droppedForA` is
  *never* delivered. Those tests must flip to assert buffered-then-flushed
  semantics, and the bound/overflow invariants need new tests.

These are design choices, not a mechanical patch → feature at `drafting`.

## Confirmed mechanism (grounded in code, 2026-07-09)

- `peer_offline` / `peer_online` **are** consumed by the extension:
  `index.ts:331-342` → `_owners.markPeerOffline(frame.peer, frame.since_ts)` /
  `markPeerOnline(frame.peer)`. The relay does emit these (the open question in
  `idea-extension-pumps-into-dead-app-peer` is resolved: **yes, the signal
  reaches the extension**).
- `OwnerMultiplexer.markPeerOffline/Online` (`owner_multiplexer.ts:432-443`)
  mutates `offlinePeerIds` and emits a one-shot `fanoutPresenceChanged`
  diagnostic (`suspended`/`resumed`) — the suspend/resume is already
  observable, just not buffered.
- `broadcast()` (`owner_multiplexer.ts:450`) is the drop site:
  ```ts
  broadcast(message: ServerMessage): void {
    for (const [peerId, channel] of this.channels) {
      if (this.offlinePeerIds.has(peerId)) continue;   // ← DROPS, must BUFFER
      try { channel.send(message); } catch { /* best-effort per owner channel */ }
    }
  }
  ```
- The inbound bounded-queue pattern to mirror lives in
  `sdk_session_projection.ts` (max 2, overflow → `internal_error`, drained on
  idle). Its overflow semantics are *not* directly reusable (online vs offline
  audience) but its *shape* (bounded, in-memory, lost on restart) is the
  reference contract.

## Design

### Design decisions

1. **Buffer location — `OwnerMultiplexer`.** Add a per-peer buffer map beside
   `channels` and `offlinePeerIds`; the multiplexer already owns fan-out,
   presence, detach, and peer-id/channel-lifetime convergence, whereas putting
   buffering in `PeerChannel` would duplicate presence policy in the transport
   adapter.
2. **Bound and overflow — one completed turn plus the active suffix, admitted
   atomically under hard shared caps.** Each offline peer retains at most one
   completed interval and the frames accumulated in the current interval
   between canonical `turn_end` boundaries, with the combined buffer capped at
   2,048 frames and 8 MiB of serialized UTF-8 payload. When admitting a current
   frame would cross either cap, evict the older completed interval atomically
   and retry; if the current interval alone still cannot fit, discard that
   entire current interval and suppress its remainder until the next boundary.
   A successfully completed current interval replaces the older completed one.
   This preserves the newest coherent turn while still allowing reconnect in
   the middle of the next turn to receive its complete buffered suffix. There
   is no reconnect marker because that would change the wire. An oversized or
   evicted turn remains recoverable only through the existing authoritative
   `session_sync`, which is an explicit limitation rather than an unbounded
   memory promise. The caps leave large headroom over the observed 18-frame
   reconnect loss while bounding both many-small-frame and one-huge-frame
   cases.
3. **Flush ordering — eager synchronous flush, with `session_sync` winning if
   it arrives before `peer_online`.** `markPeerOnline` drains the captured FIFO
   fully while the peer remains fan-out-suspended, then clears the offline bit;
   re-entrant broadcasts are appended and drained before live fan-out resumes.
   JavaScript run-to-completion prevents a sync reply from interleaving inside
   that drain. There is no request high-water mark in the current wire, so
   waiting for one could strand the buffer forever. To cover cross-socket relay
   ordering, `routeFrom` treats an inbound `session_sync` from a still-marked-
   offline peer as authoritative reconnect evidence: discard that peer's
   buffer, resume it, then route the sync so history is sent without a later
   stale flush. If `peer_online` wins first, the FIFO flush completes before a
   later sync; the app's canonical deterministic transcript-event IDs make the
   later authoritative replay idempotent.
4. **Teardown — buffer lifetime equals the managed channel lifetime.**
   `detach`, `detachAll`, relay-drop teardown, and same-peer reattach delete the
   peer's buffer as well as its offline flag; no frame survives into a new
   `PeerChannel` instance.
5. **Late attach — mutually exclusive catch-up paths by attachment lifetime.**
   A newly attached peer is online and remains a `lateAttach` target, so it gets
   the existing final `session_history` catch-up and never allocates an offline
   buffer. Reattaching an offline peer first detaches the old channel (dropping
   its buffer) and then enters the late-attach path when a turn is active. An
   already-attached peer that merely flaps stays out of `lateAttach` and gets
   only its buffered FIFO, preventing double delivery.

### Implementation units

#### Unit 1 — Bounded turn-interval buffer

**Files:** `pi-extension/src/extension/owner_multiplexer.ts`

Add a private `Map<peerId, OfflinePeerBuffer>` whose entries track at most one
completed frame interval, one current interval, combined serialized byte/frame
counts, and a `currentOverflowed` flag. Add exported, documented
`OFFLINE_BUFFER_MAX_FRAMES = 2_048` and `OFFLINE_BUFFER_MAX_BYTES = 8 * 1024 *
1024` constants plus `completeOfflineTurn()`. `broadcast()` still sends
immediately to online channels; for an offline channel it measures the
serialized frame inside a non-throwing helper, evicts the completed interval
before sacrificing the current one, or clears/suppresses the whole current
interval if it still cannot fit. An unmeasurable/cyclic payload takes the same
safe overflow path rather than escaping the existing best-effort send
boundary.

**Acceptance criteria:**
- [ ] Online fan-out is byte-for-byte and timing-equivalent to the current path.
- [ ] Each offline peer has an independent FIFO and independent cap accounting.
- [ ] A buffer never exceeds either hard cap.
- [ ] Overflow flushes no partial current interval; the next boundary permits a
      fresh interval while any still-retained completed interval remains valid.
- [ ] Serialized-size accounting cannot throw out of `broadcast()`.

#### Unit 2 — Reconnect arbitration and channel-lifetime cleanup

**Depends on:** Unit 1

**Files:** `pi-extension/src/extension/owner_multiplexer.ts`

Make `markPeerOnline()` synchronously drain buffered frames in original order
before clearing fan-out suspension and emitting `resumed`. Drain any frames
added by synchronous re-entrancy before returning. In `routeFrom`, make a
`session_sync` received while the sender is still marked offline discard its
buffer and resume before routing the authoritative request. Extend `detach()`
and aggregate teardown to delete buffer state; same-peer `attach()` must not
inherit or flush the prior channel's buffer.

**Acceptance criteria:**
- [ ] Buffered frames precede every live frame sent after `markPeerOnline()`.
- [ ] A sync-first reconnect sends no stale buffered frame after history.
- [ ] Per-frame send failures remain isolated to that owner channel and do not
      prevent state convergence to online.
- [ ] Detach, relay drop, and reattach free the old buffer.

#### Unit 3 — Canonical turn-boundary wiring

**Depends on:** Unit 1

**Files:** `pi-extension/src/extension/ports.ts`,
`pi-extension/src/index.ts`

Expose `completeOfflineTurn()` on `OwnerMultiplexerPort` and its composition
adapter. Invoke it from the existing `_applyTurnAndPublish({ type: "turn_end" })`
path so normal turns and synthetic compaction turns seal the same buffer
interval from the canonical turn-state event. Do not infer boundaries by
re-enumerating `ServerMessage.type` variants inside the multiplexer.

**Acceptance criteria:**
- [ ] Normal SDK `turn_end` and manual compaction `turn_end` each seal once
      without creating a second turn-state source of truth.
- [ ] Provider-error, cancel, and shutdown convergence retain their existing
      behavior; teardown remains the terminal buffer cleanup.
- [ ] No protocol type, relay control frame, or app behavior changes.

#### Unit 4 — Focused ordering and lifecycle regressions

**Depends on:** Units 2 and 3

**Files:** `pi-extension/src/extension/owner_multiplexer.test.ts`,
`pi-extension/src/extension.test.ts`

Update the existing suspend/resume regression and add the smallest set of tests
that proves the cap/atomic-overflow rule, flush-before-live ordering,
sync-first arbitration, teardown cleanup, canonical turn-boundary rollover,
and separation from online and late-attach paths.

**Acceptance criteria:**
- [ ] The existing test near `owner_multiplexer.test.ts:108` now expects the
      formerly dropped frame to arrive on resume before the next live frame.
- [ ] One test crosses each cap and proves that no suffix from the overflowed
      interval is flushed, then proves a post-boundary interval can flush.
- [ ] One test proves `detach`/same-peer reattach does not deliver old frames.
- [ ] One integration ordering test covers both reconnect races: `peer_online`
      first (FIFO then later idempotent history) and `session_sync` first
      (buffer discarded, history only, later `peer_online` a no-op).
- [ ] Existing online multi-owner and active-turn late-attach tests remain
      unchanged in meaning and green.

### Implementation order

1. Unit 1 — bounded turn-interval buffer.
2. Units 2 and 3 — reconnect/lifecycle policy and canonical boundary wiring.
3. Unit 4 — integrated regressions over the completed behavior.

### Testing

- **Core multiplexer regression:** flip the current suspend/resume assertion to
  buffered-then-flushed and assert an immediate post-resume broadcast follows
  the FIFO.
- **Bound/overflow:** import the exported named limits and exercise both frame-
  count and serialized-byte overflow without sleeps; prove completed-interval
  eviction happens before whole-current-interval discard, then prove recovery
  after `completeOfflineTurn()`. Include an unmeasurable payload to protect the
  best-effort error boundary.
- **Lifecycle:** buffer, detach, reattach the same peer id, then assert the new
  channel sees no stale frame. `detachAllForRelayDrop()` gets the same assertion
  through the shared cleanup path.
- **Sync ordering:** exercise the two possible relay arrival orders. The test
  protects the no-interleaving/no-stale-post-history contract rather than
  attempting to add a nonexistent wire high-water mark.
- **Non-regression:** retain the online two-owner fan-out test and the active-
  turn reattach/late-attach test; add only the assertion needed to prove those
  peers do not also receive an offline-buffer flush.

No timer or sleep is needed; all transitions are synchronous and deterministic.
Implementation verification remains the owning subproject's targeted Vitest,
then `corepack pnpm typecheck`, `corepack pnpm test`, and `corepack pnpm build`.

### Risks

- **Top risk — relay ordering versus `session_sync`.** `peer_online` and the
  reconnecting app's outer `session_sync` travel on different sockets, so their
  relative arrival is not guaranteed. The design is safe only if both branches
  are implemented: online-first drains atomically; sync-first discards before
  the authoritative reply. Failure is any trace where `session_history` is
  followed by stale buffered chunks from the same offline interval.
- **Hard-cap limitation.** A single frame or turn interval can exceed 8 MiB or
  2,048 frames. That interval is deliberately omitted rather than partially
  replayed, and the current app does not automatically request transcript sync
  on every reconnect. Such an extreme turn therefore still requires manual
  `session_sync`; eliminating that limitation belongs to the parked detection-
  lag/auto-hydration companion, not to this wire-invariant feature.

### Rollback

Revert the `OwnerMultiplexer` buffer map, `completeOfflineTurn` port/wiring, and
new tests, restoring the shipped offline `continue` drop behavior. Buffers are
process memory only and no wire, relay, app, persistence, or migration state is
introduced, so rollback has no compatibility step.

## Acceptance Criteria

- [ ] While a peer is `markPeerOffline`-offline, `broadcast()` frames are
  buffered per-peer instead of dropped.
- [ ] On `markPeerOnline`, buffered frames flush in original order before
  live fan-out resumes.
- [ ] The buffer is bounded; overflow policy is explicit and tested (per
  design decision #2).
- [ ] Buffer is freed on channel `detach`/teardown — no leak across
  re-attach.
- [ ] No regression to the online-peer fan-out path (frames still reach
  online peers immediately, unchanged).
- [ ] No regression to `lateAttach` / `session_sync` catch-up (distinct path,
  no double-delivery).
- [ ] The existing `peer_offline suspends … peer_online resumes fan-out` test
  (`owner_multiplexer.test.ts:108`) is updated to assert buffered-then-flushed
  semantics (the `droppedForA` frame must now arrive after `markPeerOnline`).
- [ ] New tests: buffer bound + overflow invariant; flush ordering; teardown
  frees buffer.
- [ ] No wire change (`PROTOCOL.md` untouched), no relay change, no app change.

## Out of scope (tracked separately)

- **Detection-lag window** (frames dropped before `peer_offline` arrives) →
  `idea-outbound-delivery-detection-lag-window` (backlog, parked this session).
- **App auto-`session_sync` on reconnect** (would make the buffer's overflow
  loss recoverable) → adjacent; if design decision #2 lands on drop-oldest,
  this becomes a desirable companion. Note in the backlog idea.
- **Cross-PC mesh `pi_envelope` delivery** → separate path
  (`story-to-room-sender-side-room-targeting`).
- **Relay-side store-and-forward** → would conflict with "relay stays opaque";
  explicitly out of scope for the known-offline window.

## Foundation-doc impact

None. No wire signal, no relay change, no app change. `PROTOCOL.md`'s
delivery-guarantee prose currently describes the inbound queued-message
semantics only; this feature adds no new wire type, so no edit is required.
If a later companion adds an app-side reconnect signal, `PROTOCOL.md` gains a
row then — not now.

## References

- Drop site: `pi-extension/src/extension/owner_multiplexer.ts:450` (`broadcast`).
- Offline set + diagnostics: `owner_multiplexer.ts:432-443`
  (`markPeerOffline`/`markPeerOnline`/`emitFanoutPresenceChanged`).
- Signal consumption: `pi-extension/src/index.ts:331-342`.
- Suspend/resume test to update: `pi-extension/src/extension/owner_multiplexer.test.ts:108`.
- Inbound bounded-queue pattern (symmetry reference):
  `pi-extension/src/session/sdk_session_projection.ts` (max 2, overflow →
  `internal_error`); overflow test at `pi-extension/src/extension.test.ts:4344`.
- Symmetric inbound feature: `.work/active/features/feature-session-stable-message-delivery.md`.
- Symptom record (open question now resolved): `.work/backlog/idea-extension-pumps-into-dead-app-peer.md`.
- Detection-lag companion (parked): `.work/backlog/idea-outbound-delivery-detection-lag-window.md`.
- Live drop evidence (2026-07-09): relay log
  `WARN relay::handlers::connection_actor: dest (peer, room) not found, dropping
  from=l2X/dUc= dest=dpOPIdc= room=main bytes=225460` (×18, app reconnected 8s later).
- Skill: `.agents/skills/pi-extension-typescript/SKILL.md` (session/owner lifecycle).

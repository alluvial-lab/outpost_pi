---
id: feature-outbound-buffer-on-peer-offline
kind: feature
stage: drafting
tags: [pi-extension, bug, lifecycle]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-09
updated: 2026-07-09
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

## Design questions (for feature-design to resolve)

1. **Buffer location.** Per-peer map on `OwnerMultiplexer` (keeps the
   multiplexer as the single fan-out authority — preferred), vs on the
   `PeerChannel`/`PlainPeerChannel` (co-locates with the send primitive, but
   the multiplexer owns the offline set and would need to delegate). Lean
   per-peer on the multiplexer; confirm at design.
2. **Bound + overflow policy.** Options:
   - (a) **Drop oldest silently** when full; rely on `session_sync` to
     backfill on reconnect. Simplest, but if reconnect doesn't auto-sync (it
     doesn't today — `requestResumeHydration` only pulls presence/rooms), the
     dropped frame is lost until manual refresh. Honest but leaky.
   - (b) **Cap at one full turn** (track turn boundaries via `turn_end` /
     `message_end`): never lose a partially-buffered turn — either the whole
     turn is buffered or the oldest *complete* turn is evicted. More complex
     but preserves turn atomicity, which matters for transcript coherence.
   - (c) **Surface a marker on reconnect** (e.g. a `delivery_pending`-style
     signal or a truncated-history hint) so the app knows to pull
     `session_sync`. Cleanest UX but edges toward a wire change — keep out of
     scope unless (a)/(b) prove insufficient.
   Lean (b) for coherence; decide at design with the turn-state projection.
3. **Flush ordering on `markPeerOnline`.** Flush buffered frames in order,
   *then* resume live fan-out. Must not race a concurrent `session_sync`
   replay (the app may request history immediately on reconnect) — if both
   fire, `session_sync` is authoritative (durable) and the buffer flush should
   be a no-op or dedupe against it. Needs a decision: does `markPeerOnline`
   flush eagerly, or wait for the app's `session_sync` to complete and only
   flush frames *newer* than the sync high-water mark?
4. **Teardown interaction.** `detach()` / channel close must drop the buffer
   (no delivery after a peer is gone for good). Confirm the buffer is
   per-`PeerChannel`-lifetime, not leaked across re-attach of the same peer id.
5. **`lateAttach` interaction.** A peer that attaches *during* an active turn
   currently gets `lateAttachTargets` / `session_sync` catch-up. The buffer is
   for a peer that was *already attached* then went offline — distinct from
   late-attach. Confirm the two paths don't double-deliver.

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

---
id: feature-app-edge-trigger-room-snapshot-consumers-opt-1
kind: story
stage: implementing
tags: [perf, app]
parent: feature-app-edge-trigger-room-snapshot-consumers
depends_on: []
release_binding: null
gate_origin: perf-design
created: 2026-08-24
updated: 2026-08-24
---

# Delete redundant room-snapshot transcript scans

## Brief

Derive one typed semantic room-snapshot edge from the canonical full room map
and make `SyncService` run held-pending replay only on a fresh-live/session
edge. The current `roomsStream` path invokes `_resendHeldPendingMessages` for
every live room snapshot; a 339-snapshot representative stream performed 339
full-log reads at 0, 200, and 5,500 events. Real encrypted Hive reads cost
20.755 ms p50 / 34.014 ms p95 at 5,500 events.

## Design

- Add a shared `RoomSnapshotChange` (or an equivalent sealed transition type)
  at the transport boundary. It must carry the canonical snapshot and a value-
  based edge classification for fresh transport/live confirmation, session-id
  rotation, presentation metadata, and no-op.
- Keep the existing full `roomsStream` as canonical source-of-truth output;
  the derived edge is a dispatch contract, not a second room/transcript cache.
- Change `SyncService`'s room listener and `_handleRoomsChanged` to consume the
  edge. Working/model/name-only changes must not call
  `_resendHeldPendingMessages`; fresh room confirmation and session rotation
  must still perform one guarded sweep.
- Preserve channel/liveness re-checks after every await, stale-room gating,
  original client-id resend dedupe, and active-session generation fencing.

## Benchmark checkpoint

Location: `app/test/perf/room_snapshot_consumers_benchmark_test.dart`.
Remove its design-only skip during implementation. For 339 metadata/working
snapshots over 0/200/5,500-event stores, assert `snapshot_reads == 0` after the
change (initial setup reads excluded). Add focused scenarios asserting exactly
one read/replay after fresh reconnect room confirmation and after session-id
rotation. Keep the working-false convergence and no-anchor oracles.

## Acceptance Criteria

- [ ] Shared edge classification is derived from canonical room snapshots and
      does not add sticky state or a transcript cache.
- [ ] Metadata/working churn performs zero full transcript reads and zero held
      replay sends when session identity and liveness are unchanged.
- [ ] Fresh reconnect confirmation and session rotation each perform one
      guarded replay sweep when needed.
- [ ] Stale-room gating, held resend, reconnect hydration, session replacement,
      and `working:false` tests pass.
- [ ] Benchmark before/after output records the read-count movement and the
      real-Hive baseline remains cited separately from fake traversal timing.

## Likely files

- `app/lib/data/transport/room_snapshot_change.dart` (new, if the derived
  contract is not kept beside `ConnectionManager`)
- `app/lib/data/transport/connection_manager.dart`
- `app/lib/data/sync/sync_service.dart`
- `app/test/data/transport/connection_manager_test.dart`
- `app/test/data/sync/sync_service_test.dart`
- `app/test/perf/room_snapshot_consumers_benchmark_test.dart`

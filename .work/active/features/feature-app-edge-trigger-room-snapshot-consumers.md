---
id: feature-app-edge-trigger-room-snapshot-consumers
kind: feature
stage: implementing
tags: [perf, app]
parent: epic-perf-optimization-campaign
depends_on: []
release_binding: null
gate_origin: perf-design
created: 2026-08-24
updated: 2026-08-24
---

# Make room-snapshot consumers edge-triggered

## Brief

Bottleneck: the `roomsStream` listeners in
`app/lib/data/sync/sync_service.dart` and
`app/lib/ui/chat/viewmodels/chat_viewmodel.dart`. Every canonical room snapshot
schedules runtime/session work; a live bound session reaches
`SyncService._resendHeldPendingMessages`, which performs a full transcript-event
read and scan even when there are no held messages, while `ChatViewModel`
serializes a binding refresh and recomputes immediately and again after that
async path. The partial 159-second device soak observed **10 room snapshots**;
the motivating 11-hour capture had **339**. At the 5,500-event stress size, the
actual encrypted Hive `readSession` called by the resend sweep cost **20.755 ms
p50 / 34.014 ms p95**, so 339 metadata snapshots can imply about **7.0 seconds
of full-log read time** before ViewModel rebuild work. Proposed hierarchy level:
**Algorithmic / data model** and **I/O / service boundary**, with **workload,
storage-I/O, and UI fan-out** probes.

## Optimization direction for the design pass

Classify room emissions at the boundary into the semantic edges consumers need:
transport-generation/liveness transition, session-id rotation, relevant active-
room metadata change, and no relevant change. Session rebind and held-send
replay should run only for their owning edge; presentation should recompute once
per semantic change. Preserve full canonical snapshots as the source of truth —
do not add a second stale cache or debounce away convergence.

The transcript anchoring callback is not the diagnosed source: `_MessageList`
only schedules it when message identities or streaming content change. The
design should prevent room-only notifications from causing unnecessary chat
rebuilds rather than weakening anchor restoration.

## Simplification opportunity

Delete the unconditional room-snapshot transcript scan, duplicate
`ChatViewModel._recompute` path, and rebind work for unchanged session identity.
Prefer one derived edge/event over additional sticky booleans.

## Discovery constraints for perf-design

- Benchmark 339 snapshots against empty, 200-event, and 5,500-event sessions;
  count Hive reads, binding refreshes, `notifyListeners`, widget rebuilds, and
  post-frame anchor callbacks.
- Preserve reconnect hydration, session rotation, held-pending resend, stale
  room gating, multi-client updates, and `working:false` convergence.
- Use explicit stream barriers/fake clocks rather than elapsed-time sleeps for
  lifecycle correctness tests.

## Perf Overview

The measured hot path is the canonical room snapshot fan-out after the relay
control decoder: `ConnectionManager.roomsStream` emits a full room map, then
`SyncService`, `ChatViewModel`, and `HomeViewModel` all receive the same event.
The relevant current work is:

1. `SyncService` schedules `_handleRoomsChanged`; for a live bound room it calls
   `_resendHeldPendingMessages`, which reads and scans the complete transcript
   even when the snapshot only changes `working`, `model`, or another field
   unrelated to held-send recovery.
2. `ChatViewModel` schedules `_handleRoomsChanged` and immediately calls
   `_recompute`; the async path then serializes a binding refresh through
   `_bindingChain` and can recompute again. The `SyncService.activate` fast path
   avoids a second disk operation today, but the binding attempt and projection
   work remain on every snapshot.
3. `HomeViewModel` consumes the full snapshot and emits a new `HomeList` for
   every canonical change. Its broad page listener is correct but makes each
   accepted room update a whole Home surface rebuild. Exact duplicate snapshots
   are already filtered in `ConnectionManager`; the remaining opportunity is
   semantic edge filtering and avoiding consumer work that cannot affect the
   relevant surface.

The fix is **edge-triggered semantic change detection plus shared derived state**,
not a transcript cache. Canonical full snapshots remain the source of truth;
held replay runs on a fresh-live/session edge, binding runs on session identity
change, presentation recomputes on presentation changes, and identical/no-op
snapshots do no consumer work. No debounce may hide a genuine `working:false`
transition or stale-room gate.

## Profiling Summary

### Workload and tools

- Host: Linux, 8 vCPU, 16 GiB; Flutter 3.44.4 / Dart 3.12.2.
- Probe: `flutter_test` widget harness with a populated fake
  `TranscriptEventStore`, a representative 339-snapshot stream, and
  `ListenableBuilder` probes for Chat/Home rebuilds. The harness counts
  `readSession`, `SyncService.activate`, `notifyListeners`, widget builds, and
  transcript-anchor callbacks.
- Run command for the implementation pass:
  `cd app && flutter test --no-pub test/perf/room_snapshot_consumers_benchmark_test.dart --reporter expanded`
  Remove the design-only `skip: true` only when the implementation story adds
  the explicit async teardown barrier and before/after assertions.
- Dart DevTools is installed, but the device/integration lane exposes no stable
  VM-service URI for headless CPU/allocation attachment. `perf` is unavailable
  and `perf_event_paranoid=3`; this is an application fan-out/I/O problem rather
  than a low-level CPU-bound loop, so hardware-counter evidence is not required.

### Baseline: representative 339-snapshot stream

The fake-store values below measure the consumer fan-out and a deterministic
full-list traversal; they are not a replacement for the encrypted Hive number.
The initial two reads are setup/materialization and are excluded from the
per-snapshot counters.

| Fake transcript events | `readSession` p50/p95 | Snapshot wall p50/p95 | Full reads | Binding refreshes | Chat/Home notify | Chat/Home builds | Anchor callbacks |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 2 / 4 us | 0.882 / 1.498 ms | 339 | 339 | 339 / 339 | 339 / 339 | 0 |
| 200 | 2 / 14 us | 0.715 / 1.364 ms | 339 | 339 | 339 / 339 | 339 / 339 | 0 |
| 5,500 | 55 / 163 us | 0.753 / 1.639 ms | 339 | 339 | 339 / 339 | 339 / 339 | 0 |

The real encrypted Hive evidence from discovery is **20.755 ms p50 / 34.014
ms p95 per full 5,500-event `readSession`**. Thus 339 snapshots imply about
**7.04 seconds p50 full-log read time** (and about 11.53 seconds at the p95
read figure) before ViewModel/UI work. The fake traversal isolates fan-out
cost; it intentionally does not claim to reproduce Hive encryption latency.

The anchor count is zero by design: room metadata does not change message
identities or streaming content, and `_MessageList.didUpdateWidget` gates
`addPostFrameCallback` on those transcript edges. The benchmark must keep this
oracle at zero for room-only churn while retaining a separate transcript-change
anchor test.

### Diagnosis by hierarchy

- **Algorithmic / data model (primary):** one full transcript read and scan is
  repeated per room snapshot although held-send recovery only needs a fresh
  live-room/session edge. This is redundant work, not irreducible data access.
- **I/O / service boundary (secondary):** the redundant algorithmic decision
  crosses into encrypted Hive; deleting the call removes a full storage read,
  not merely a faster read.
- **UI fan-out:** Chat's binding/recompute path and Home's broad listener are
  downstream work on the same event. Presentation must still react once to
  genuine active-room metadata/liveness changes.
- **Not proposed:** a sticky transcript cache, a debounce that can erase
  convergence, or parallel reads. All are lower-quality responses to work that
  can be deleted.

## Optimization Plan

### Optimization 1: Derive shared semantic room edges and gate held replay

**Hierarchy Level**: Algorithmic / Data Model, deleting redundant I/O at the service boundary
**Probe Family**: Workload baseline, storage-I/O, UI fan-out
**Bottleneck**: `_resendHeldPendingMessages` reads and scans the full active
transcript from `_handleRoomsChanged` for every live `roomsStream` event. The
339-snapshot harness measured 339 snapshot reads at every transcript size; the
real 5,500-event Hive read is 20.755 ms p50.
**Expected Metric Movement**: Metadata/working churn changes from 339 full
reads and 339 held replay passes to zero full reads and zero replay passes.
A fresh reconnect confirmation, room liveness edge, or session rotation still
performs exactly one guarded sweep. This deletes approximately 7.04 seconds of
p50 Hive read time from the 339-snapshot field scenario.
**Story**: `feature-app-edge-trigger-room-snapshot-consumers-opt-1`

#### Implementation Units

##### Unit 1.1: Publish one derived room-snapshot edge beside the canonical snapshot

**File**: `app/lib/data/transport/room_snapshot_change.dart` (new),
`app/lib/data/transport/connection_manager.dart`

```dart
sealed class RoomSnapshotChange {
  const RoomSnapshotChange({required this.snapshot});
  final Map<String, List<RoomInfo>> snapshot;
}

final class RoomSnapshotMetadataChanged extends RoomSnapshotChange {
  const RoomSnapshotMetadataChanged({required super.snapshot});
}

final class RoomSnapshotSessionRotated extends RoomSnapshotChange {
  const RoomSnapshotSessionRotated({required super.snapshot});
}

final class RoomSnapshotNoop extends RoomSnapshotChange {
  const RoomSnapshotNoop({required super.snapshot});
}
```

**Implementation Notes**:

- Prefer one compact typed edge/transition object (or an equivalent sealed
  representation) derived from the existing canonical full map. Do not create a
  second transcript/session cache and do not re-enumerate protocol variants.
- Derive the edge at the `ConnectionManager` emission boundary, where the
  previous canonical snapshot, current active room, live set, and transport
  generation are already known. Keep `roomsStream` intact for existing full
  snapshot consumers while adding the shared derived stream for lifecycle
  consumers.
- Treat transport-generation/fresh-live confirmation and session-id rotation
  as replay/binding edges. Treat `working`, model/thinking, name/cwd, and
  liveness changes as presentation edges. Treat identical/no-relevant changes
  as no-op. A `working:false` transition must never be dropped.

**Acceptance Criteria**:

- [ ] The derived edge is value-based and comes from the canonical snapshot;
      no sticky boolean or transcript cache is introduced.
- [ ] Exact duplicate snapshots remain no-op, while session rotation,
      fresh-room confirmation, and `working:false` produce explicit edges.
- [ ] Existing `roomsStream` consumers and room/session selection behavior stay
      source-compatible.

##### Unit 1.2: Run held replay only on its owning edge

**File**: `app/lib/data/sync/sync_service.dart`

```dart
Future<void> _handleRoomsChanged(RoomSnapshotChange change);
Future<void> _resendHeldPendingMessages(
  int generation,
  RemoteSessionRef ref,
);
```

**Implementation Notes**:

- Change the `_roomsSub` listener to consume the shared edge. Keep
  `_writeRuntime` on the appropriate liveness/runtime edge, but do not call
  `_resendHeldPendingMessages` for working/model/name-only changes.
- Preserve the existing active-channel and `isRoomLive` re-checks after every
  await. On session rotation, activate the new `RemoteSessionRef` before
  replay. On a relay reconnect, wait for the authoritative fresh room
  confirmation before reading or resending.
- The benchmark's current assertion of one read per snapshot becomes an
  after-assertion of zero for metadata-only churn plus a focused one-read
  assertion for fresh reconnect/session-rotation edges.

**Acceptance Criteria**:

- [ ] 339 metadata/working snapshots perform zero full transcript reads and
      zero held-message sends when the session identity and liveness edge are
      unchanged.
- [ ] A held pending message is still resent after fresh room confirmation,
      with the original client id and existing dedupe behavior.
- [ ] Stale-room gating, session rotation, reconnect hydration, and
      `working:false` convergence tests remain green.

---

### Optimization 2: Coalesce consumer work without suppressing genuine changes

**Hierarchy Level**: Algorithmic / Data Model (consumer edge routing)
**Probe Family**: UI fan-out, workload baseline
**Bottleneck**: `ChatViewModel` handles the same snapshot in two phases: an
immediate `_recompute` and a serialized async binding path that can recompute
again. `HomeViewModel` receives every canonical change through a broad list
state, even when the change is not relevant to the current presentation edge.
The baseline has one observable notification/build per working snapshot, but it
still performs redundant projection/binding calls and offers no explicit
no-op edge contract.
**Expected Metric Movement**: For a metadata-only active-room update, Chat has
one projection pass and no binding refresh; for a no-op snapshot, Chat and Home
have zero `notifyListeners`/widget builds. For a genuine active-room working,
liveness, or session edge, each consumer still has exactly one notification and
one build. Post-frame anchor callbacks remain zero for room-only churn.
**Why higher levels don't apply**: The remaining work is not an I/O or cache
problem; it is duplicate consumer dispatch. Removing the duplicate dispatch is
the algorithmic fix.
**Story**: `feature-app-edge-trigger-room-snapshot-consumers-opt-2`

#### Implementation Units

##### Unit 2.1: Bind Chat only on identity/liveness edges and recompute once

**File**: `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`

```dart
StreamSubscription<RoomSnapshotChange>? _roomChangesSub;
Future<void> _handleRoomsChanged(RoomSnapshotChange change);
Future<void> _refreshSessionBinding(int generation);
```

**Implementation Notes**:

- Replace the current `roomsStream.listen((_) { unawaited(...); _recompute(); })`
  split with one edge-aware handler. Metadata that affects the active room's
  turn projection recomputes once; session identity/transport edges serialize
  binding and then recompute once after the binding result.
- Keep `ChatViewModel._activeSessionRef` and the existing generation guards as
  lifecycle authorities. Do not turn `activate` into a sticky cache or use a
  timer/debounce to hide a session replacement.
- Leave transcript anchor semantics untouched: `_MessageList` must continue to
  schedule restoration only when message identities or streaming content change.

**Acceptance Criteria**:

- [ ] Same-session working/model changes do not invoke a binding refresh.
- [ ] Every genuine session rotation rebinds once and cannot paint stale rows.
- [ ] Each accepted active-room presentation edge emits at most one ViewModel
      notification; `working:false` still reaches idle.
- [ ] Room-only churn produces zero post-frame anchor callbacks.

##### Unit 2.2: Make Home consume the shared presentation edge

**File**: `app/lib/ui/home/viewmodels/home_viewmodel.dart`,
`app/lib/ui/home/states/home_state.dart` (only if a typed presentation
projection is needed)

```dart
void _onRoomChange(RoomSnapshotChange change);
void _onRooms(Map<String, List<RoomInfo>> snapshot); // retained for canonical UI state
```

**Implementation Notes**:

- Preserve the complete canonical room data needed by Home's open-session
  route (`roomId` and `sessionId`) and selection highlighting. Filter only
  changes that cannot affect Home's visible rooms/presence/working/liveness;
  never drop a session edge that affects the selected-room reference.
- Prefer `context.select`/item-level consumption if the widget tree needs a
  narrower rebuild, but do not duplicate room maps in state. A full-list
  rebuild is acceptable for a genuinely changed Home presentation edge; it is
  not acceptable for a no-op edge.
- Keep the existing storage listener, filter tab state, and offline-room
  behavior unchanged.

**Acceptance Criteria**:

- [ ] An irrelevant/no-op room edge causes no Home notification or widget
      rebuild.
- [ ] Working, liveness, name/cwd/model, room add/remove, and selected-session
      rotation still update the correct tile exactly once.
- [ ] Home continues to show authoritative `working:false` after turn end,
      reconnect, room end, and session switch.

## Benchmarks

**Location**: `app/test/perf/room_snapshot_consumers_benchmark_test.dart`
**Run command**: `cd app && flutter test --no-pub test/perf/room_snapshot_consumers_benchmark_test.dart --reporter expanded`
**Baseline targets**: 339 full-log reads and 339 binding refresh calls for each
of the 0/200/5,500-event representative stores; fake-store read/wall values are
tabled above; real encrypted Hive 5,500-event read is 20.755 ms p50 / 34.014 ms
p95. Chat/Home each notify and rebuild once per working snapshot; anchor count
is zero.
**Expected targets**:

- Metadata/working churn with unchanged session/liveness: `snapshot_reads = 0`,
  `binding_refreshes = 0`, one Chat/Home notification only when the visible
  working state changes, and `post_frame_anchor_callbacks = 0`.
- Identical/no-op snapshots: zero reads, binding refreshes, notifications,
  rebuilds, and anchor callbacks.
- Fresh reconnect/session rotation: one guarded binding/read/replay pass, with
  held messages delivered once and no stale-session rows.
- Genuine `working:false`: one presentation notification and convergence to
  idle.

**Counter targets**: `readSession` calls, `_sync.activate`/binding attempts,
`notifyListeners`, consumer widget builds, post-frame anchor callbacks, and
per-snapshot wall time. The implementation pass should also record a separate
real-Hive run if the host allows it; do not treat fake traversal microseconds as
device storage latency.

## Implementation Order

1. `feature-app-edge-trigger-room-snapshot-consumers-opt-1` — derive the shared
   semantic edge and delete redundant transcript scans; establish the reconnect,
   session-rotation, held-replay, and `working:false` oracle matrix.
2. `feature-app-edge-trigger-room-snapshot-consumers-opt-2` — route Chat/Home
   through the edge, remove duplicate binding/recompute dispatch, and verify the
   widget counters and anchor oracle against the same representative stream.
3. Remove the benchmark scaffold's design-only skip, run before/after on the
   0/200/5,500-event stores, then run the bounded app test suite.

## Implementation Results

Both planned optimizations landed in dependency order.

- **Opt 1 — semantic room edges / held replay:** metadata-only churn moved from
  **339 full transcript reads to 0** for 0/200/5,500-event fixtures. The focused
  fresh-live oracle performs exactly one liveness-gated read; session rotation
  remains generation-fenced and held sends retain their original client id.
  Against the encrypted-Hive baseline, this deletes about **7.04 s p50** (up to
  **11.53 s** at the p95 read figure) from the 339-snapshot field workload.
- **Opt 2 — Chat/Home fan-out:** same-session churn moved from **339 Chat binding
  refreshes to 0**. The 339 genuine alternating working edges still produce
  exactly **339/339 Chat/Home notifications and rebuild callbacks**; an equal
  snapshot produces zero reads, bindings, notifications, rebuild callbacks, or
  transcript-anchor callbacks. Session rotation binds Chat once and
  `working:false` converges once to idle.
- Isolated final host-side wall p50/p95 was **41/62 us** (0 events), **35/53 us**
  (200), and **29/57 us** (5,500), versus **0.882/1.498 ms**,
  **0.715/1.364 ms**, and **0.753/1.639 ms** before. These listener/fake-store
  timings measure consumer fan-out, not encrypted storage latency.
- The benchmark is enabled with explicit listener/subscription/controller
  teardown and retains the room-only anchor scheduling oracle at zero.
- Concurrent transcript-pipeline work landed first. The room-consumer changes
  were rebased onto that reducer/store surface; no projection/reducer internals
  were changed by this feature.

Verification: `flutter analyze` is clean; targeted transport/sync/Chat/Home and
benchmark tests pass; the full app suite passes with **937 tests** under
`flutter test --exclude-tags e2e --concurrency=2`.

## Review closure (2026-08-24)

The required end-to-end validation is green but shows no measurable win for this
optimization at the exercised scale. The 300-second soak emitted **18** room
snapshots and ended with **11** transcript rows, far below the motivating
339-snapshot/5,500-event case. On the same capture-timestamp method used for
discovery, online→authoritative room snapshot moved from **13.807 ms p50 /
184.485 ms p95** (n=8) to **16.365 ms p50 / 188.986 ms p95** (n=11); that is no
improvement, not a speedup claim. The eliminated 339→0 full reads remain useful
for long-lived rooms with large hydrated transcripts, where the removed work
scales with both snapshot count and log size; this short low-volume soak cannot
make that avoided I/O visible. The same run preserved replay, DB↔projection,
rendering, ordering, and identity oracles. Closure verification also passed the
clean analyzer and full non-e2e app suite (**940 passed**).

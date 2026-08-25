---
id: gate-cruft-room-snapshot-benchmark-scaffolding
kind: story
stage: done
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: cruft
created: 2026-08-25
updated: 2026-08-25
---

# Remove superseded baseline scaffolding from the room-snapshot benchmark

## Confidence
High

## Category
Low-value test / obsolete performance-campaign scaffold

## Relevance
Release-relevant: the after-optimization benchmark no longer performs the baseline read path.

## Location
`app/test/perf/room_snapshot_consumers_benchmark_test.dart:62-66, 246-296`

## Evidence
```dart
void pushServer(ServerMessage msg) => _messages.add(msg);
void pushControl(ControlInbound frame) {
  _controls.add(frame);
}

final List<int> readDurationsUs = <int>[];
final List<Completer<void>> _readWaiters = <Completer<void>>[];
// ...
Future<void> waitForReadCount(int expected) { /* ... */ }
```

Neither channel pusher is called, and `waitForReadCount` plus `readDurationsUs` have no callers in the current after-optimization benchmark. They belong to the removed baseline assertion that expected one transcript read per snapshot.

## Removal rationale
Delete the unused channel pusher methods and the read-timing/waiter machinery, including the completion block in `readSession`. Retain `readCalls` and the deterministic traversal because the benchmark still asserts zero snapshot reads after initialization.

## Risk
None to production code or benchmark coverage. The live benchmark continues to measure the no-read invariant and its existing lifecycle/session assertions.

## Implementation
- Proof: file-local grep found both channel pushers only at their declarations and found the timing list, waiter list, and `waitForReadCount` only within their self-contained completion scaffold. `readCalls` remains asserted throughout the benchmark.
- Removal: deleted the unused channel pushers and read-duration/waiter machinery, including stopwatch collection and waiter completion; retained `readCalls`, the defensive full traversal, and zero-read assertions.
- Verification: `flutter test test/perf/room_snapshot_consumers_benchmark_test.dart` passed and emitted all three benchmark cases with `snapshot_reads: 0`. The release-wide app analyze and full non-E2E suite are recorded in the gate-fix completion report.
- Execution capability: sol/high; direct-read cleanup with grep and benchmark evidence.
- Adjacent issues parked: none.

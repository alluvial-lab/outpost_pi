---
id: feature-app-incremental-transcript-projection-pipeline
kind: feature
stage: done
tags: [perf, app]
parent: epic-perf-optimization-campaign
depends_on: []
release_binding: v0.8.0
gate_origin: perf-design
created: 2026-08-24
updated: 2026-08-24
---

# Incremental transcript append and projection pipeline

## Brief

Bottleneck: `app/lib/data/sync/sync_service.dart` (`_appendTranscriptEvents`,
`_rewriteMessageProjectionInWriteChain`, `_timestampForProjectedMessage`),
`app/lib/domain/transcript/transcript_projection.dart`
(`deriveTranscriptProjection`), and
`app/lib/data/local/transcript_event_store_hive.dart`. Every accepted append can
scan the event box for sequence, append, read and decode the complete log,
rederive the complete projection, rescan the log once per projected message for
timestamps, and compare/rewrite the disposable message projection.

Discovery measured pure projection p50 at **0.690 ms for 200 events**, **5.577
ms for 1,000**, and **198.813 ms for 5,500** (p95 211.371 ms). The original
harness metadata said 2,750 messages, but its recovered generator alternated one
confirmed user and one committed assistant event; the asserted projection
contains **5,500 messages**. Rebuilding after every prefix append took
**1,330.628 ms total for 1,000 events**. The actual encrypted Hive store took
**859.471 ms to batch-append 5,500 events** and a full read took **20.755 ms p50
/ 34.014 ms p95**.

## Optimization direction

Use a canonical incremental reducer/materialization boundary. Accepted new
events update event identity, ordering metadata, turn/steering state, timestamps,
and affected message rows once. Full-log rebuild remains the explicit
activation/recovery path, not the default append path. The event-store append
receipt carries the accepted events and assigned sequence values, eliminating
the append-then-`readSession` round trip and independent dedupe traversal.

This is not a memoization cache. The append-only event log remains truth; the
existing `msgs` box remains a disposable materialized projection. The same
reducer performs both incremental application and clean full rebuild, and the
clean rebuild is the equivalence oracle.

## Design decisions

- **Direct-read grounding:** this was a bounded, known app seam. The design pass
  read the full reducer/store contracts and implementations, the complete write
  chain around activation, append, replay, recovery, materialization, lifecycle
  fencing, and the existing projection/store/sync tests. No exploratory
  subagent adapter was available in this execution context; direct reading was
  both the fallback and the lower-cost evidence path.
- **One reducer, not two algorithms:** `deriveTranscriptProjection` becomes a
  fold through the incremental reducer. Recovery and append cannot drift.
- **Delta is an affected suffix:** canonical server-time backfill can insert in
  the middle, so a delta is not always one row. It identifies the first changed
  message index; normal live traffic changes a tail row, while replay backfill
  may rewrite the affected suffix.
- **No parallelism or cache:** repeated work is algorithmic and storage-bound.
  Concurrency would complicate lifecycle ownership without removing it; a cache
  would duplicate the disposable materialized state and add invalidation.
- **Recovery stays explicit:** activation and an all-duplicate replay used to
  repair an empty/corrupt disposable box may perform `readSession` and a clean
  fold. Normal accepted appends may not.

## Perf Overview

The rerun used the checked-in Dart/Flutter test timing harness on the discovery
host (Linux, 8 logical CPUs, Dart 3.12.2). It preserved the recovered discovery
fixture: 5,500 alternating `UserMessageConfirmed` and
`AssistantMessageCommitted` events, producing 5,500 projected messages. The
isolated shape rerun measured **182.262 ms p50 / 198.995 ms p95** at 5,500,
confirming the discovery tail within normal test-process/JIT variance. The
1,000-prefix rebuild measured **1,314.045 ms**, effectively reproducing the
1,330.628 ms discovery result.

Encrypted Hive also reproduced: 5,500 batch append **790.356 ms**, read **21.088
ms p50 / 21.840 ms p95**, versus discovery 859.471 ms and 20.755/34.014 ms.
Read plus projection was **160.594 ms p50 / 168.291 ms p95**, 7.6x the store
read alone. A new append-shape probe measured 1,000 events at **109.623 ms in one
batch** versus **952.163 ms one at a time**, localizing the repeated `_maxSeq`
decode and per-event Hive awaits.

What the fix deletes:

- append-time full `readSession` and complete projection derivation;
- quadratic per-user reply-anchor searches;
- `_timestampForProjectedMessage`'s projected-message × event-log scans;
- full-row comparison loops for unaffected message prefixes;
- `_maxSeq(box.values)` on every append;
- dead `_idToSeq` / `_nextSeq` reconstruction once deltas own row positions.

## Profiling Summary

### Probe/tool posture

- **Workload:** Stopwatch p50/p95 with warmup, 200/1,000/5,500 events, one replay
  batch, and one-at-a-time prefixes/appends. Raw rerun output is local-only at
  `.work/session-notes/perf-discovery-20260824/app-transcript-pipeline-redesign.raw.txt`.
- **On-CPU localization:** workload-shape isolation was used because the hot
  function is pure Dart. At 5,500 events, assistant-only projection was **7.854
  ms p50**, alternating user/assistant was **182.262 ms**, and user-only was
  **211.875 ms**. The differentiator is the final per-user `indexWhere` reply
  anchoring loop, not parsing or assistant folding.
- **Storage I/O:** real encrypted Hive append/read probes were retained. The
  one-at-a-time append shape is 8.7x the batch shape at 1,000 events.
- **Memory:** `ProcessInfo.currentRss` remains a coarse cumulative signal. The
  rerun reached about 160 MiB after projection shapes and 179 MiB after the Hive
  shapes; discovery rose from 135.4 MiB to 156.7 MiB during projection. These
  are not allocations/op and no allocation target is claimed.
- **DevTools limitation:** `dart devtools` is installed, but this one-shot
  headless Flutter test lane does not expose a stable service URI to the
  harness, and no browser DevTools attachment is available. Allocation and CPU
  flamegraph capture remain unavailable here. `dart test` also has no direct
  `package:test` dependency; the repository-standard `flutter test` runner is
  used instead of adding a dependency solely for this benchmark.
- **Microarchitecture/off-CPU:** skipped. This is a single-isolate, high-level
  Dart algorithm/storage path with measured quadratic work and no lock or
  scheduler symptom. Hardware counters would not change the hierarchy choice;
  validate the algorithmic/I/O fixes before considering lower-level probes.

### Ranked hot spans

1. **`deriveTranscriptProjection` reply anchoring** — Algorithmic/data model,
   on-CPU. For every projected user, two linear `indexWhere` searches and a
   possible list move make the final pass quadratic. Assistant-only 5,500 is
   7.854 ms p50; user-bearing shapes are 182-212 ms.
2. **Whole-prefix rebuild on every append** — Algorithmic/data model, workload.
   Reprocessing all prior events for 1,000 one-at-a-time prefixes costs 1.314 s.
3. **Hive sequence scan and per-record writes** — Algorithmic/data model + I/O.
   `_maxSeq` decodes all box values before each append; 1,000 one-at-a-time
   appends cost 952.163 ms versus 109.623 ms in one batch.
4. **Append-read-project-materialize chain** — Algorithmic/data model + I/O.
   Accepted append rereads the entire log, then full derivation, timestamp scans,
   and every-row comparisons. Read+derive alone is 160.594 ms p50 before the
   uninstrumented timestamp/materialized-row passes.

## Optimization Plan

### Optimization 1: Canonical incremental transcript reducer

**Hierarchy Level**: Algorithmic / data model
**Probe Family**: Workload baseline, on-CPU, memory/RSS
**Bottleneck**: Full derivation repeats every prior event and ends with a
quadratic user/reply anchoring pass. The 5,500-event user-bearing shapes cost
182-212 ms p50 while assistant-only costs 7.854 ms.
**Expected Metric Movement**: Replace repeated full folds with accepted-event
application; remove the quadratic anchor pass. Target <=40 ms p50 / <=60 ms p95
for a clean 5,500-event fold and <=100 ms total for 1,000 timed incremental
applications. Complexity moves from quadratic scans/repeated prefixes toward
`O(k + changed ordering work)` per accepted batch, with tail appends amortized
constant-time outside projection snapshot creation.
**Story**: `feature-app-incremental-transcript-projection-pipeline-opt-1`

#### Implementation Units

##### Unit 1.1: Reducer and update contract
**File**: `app/lib/domain/transcript/transcript_projection.dart`

```dart
final class TranscriptProjectionReducer {
  factory TranscriptProjectionReducer.empty({required String sessionId});

  TranscriptProjectionUpdate applyAll(Iterable<TranscriptEvent> events);
  TranscriptProjection get projection;
}

final class TranscriptProjectionUpdate {
  const TranscriptProjectionUpdate({
    required this.acceptedEvents,
    required this.projection,
    required this.firstChangedMessageIndex,
  });

  final List<TranscriptEvent> acceptedEvents;
  final TranscriptProjection projection;
  final int? firstChangedMessageIndex;
}

final class TranscriptProjection {
  const TranscriptProjection({
    required this.messages,
    required this.messageTimestamps,
    required this.turn,
    required this.steering,
    this.streaming,
  });

  final List<ChatMessage> messages;
  final List<DateTime> messageTimestamps;
  // Existing streaming/turn/steering fields remain.
}

TranscriptProjection deriveTranscriptProjection({
  required String sessionId,
  required Iterable<TranscriptEvent> events,
});
```

**Implementation Notes**:
- Fold event variants once into keyed state. Batch new authoritative rows, sort
  by canonical server time + stable arrival, and merge; optimize the normal
  monotonic tail without changing replay backfill order.
- Maintain prompt/reply relationships by keyed identity, not repeated list
  searches. Preserve the current prompt-before-named-reply safety invariant.
- Keep message and timestamp lists aligned and immutable at the published seam.
- Full derivation constructs an empty reducer and calls `applyAll`; it must not
  retain the old implementation as a parallel oracle.

**Acceptance Criteria**:
- [ ] Incremental and clean-fold projections match at every generated prefix.
- [ ] 5,500-event clean fold <=40 ms p50 / <=60 ms p95 on this host.
- [ ] 1,000 timed incremental applies <=100 ms excluding oracle work.
- [ ] Existing transcript ordering, dedupe, tool, streaming, steering, and turn
      tests pass.

---

### Optimization 2: Accepted append receipts and batched Hive writes

**Hierarchy Level**: Algorithmic / data model, then I/O / service boundary
**Probe Family**: Storage I/O, workload baseline
**Bottleneck**: `HiveTranscriptEventStore.appendAll` calls `_maxSeq` over all
records and awaits `box.put` for every accepted event. 1,000 one-at-a-time
appends cost 952.163 ms; 5,500 in one batch still costs 790.356 ms.
**Expected Metric Movement**: Eliminate `n` prior-record sequence scans across
`n` appends, reduce replay persistence from N Hive awaits to one batched write,
and return accepted entries directly. Targets: <=400 ms for 1,000 one-at-a-time,
<=50 ms for a 1,000 batch, and <=250 ms for a 5,500 batch.
**Why higher levels don't apply**: The sequence ownership defect is itself
algorithmic and is addressed first; batching is the remaining I/O-boundary win.
**Story**: `feature-app-incremental-transcript-projection-pipeline-opt-2`

#### Implementation Units

##### Unit 2.1: Rich append and clear contract
**File**: `app/lib/domain/contracts/transcript_event_store.dart`

```dart
final class SequencedTranscriptEvent {
  const SequencedTranscriptEvent({
    required this.event,
    required this.sequence,
  });
  final TranscriptEvent event;
  final int sequence;
}

final class AppendTranscriptEventsResult {
  const AppendTranscriptEventsResult({
    required this.received,
    required this.appended,
    required this.skipped,
    required this.accepted,
  });
  final int received;
  final int appended;
  final int skipped;
  final List<SequencedTranscriptEvent> accepted;
}

abstract interface class TranscriptEventStore {
  Future<AppendTranscriptEventsResult> appendAll(
    TranscriptSessionKey key,
    Iterable<TranscriptEvent> events,
  );
  Future<void> clearSession(TranscriptSessionKey key);
  Future<List<TranscriptEvent>> readSession(TranscriptSessionKey key);
}
```

##### Unit 2.2: Constant-time sequence ownership and batch persistence
**File**: `app/lib/data/local/transcript_event_store_hive.dart`

```dart
@override
Future<AppendTranscriptEventsResult> appendAll(
  TranscriptSessionKey key,
  Iterable<TranscriptEvent> events,
);

@override
Future<void> clearSession(TranscriptSessionKey key);
```

**Implementation Notes**:
- The per-session box is append-only between full clears; use that invariant for
  constant-time next-sequence ownership, and put clear/reset behind the same
  adapter contract.
- Deduplicate against persisted keys and a batch-local set before building the
  `putAll` map so the first occurrence keeps current semantics.
- Return only successfully accepted entries, in assigned sequence order.

**Acceptance Criteria**:
- [ ] Existing logs reopen in identical order and clear resets allocation.
- [ ] Duplicate-first-wins and wrong-session fail-fast behavior remain exact.
- [ ] Batch and one-at-a-time benchmarks meet their targets.
- [ ] Store and sync fake tests pass with the richer receipt.

---

### Optimization 3: Receipt-driven delta materialization in SyncService

**Hierarchy Level**: Algorithmic / data model, with I/O / service-boundary payoff
**Probe Family**: On-CPU, storage I/O, workload latency, memory/RSS
**Bottleneck**: Every accepted append performs `readSession`, a clean fold,
message × log timestamp scans, and comparisons across the complete disposable
projection. Read+fold is already 160.594 ms p50 at 5,500 before timestamp and
row-materialization work.
**Expected Metric Movement**: Normal append reads 1 -> 0; timestamp log scans ->
0; row comparisons/writes from all messages -> affected suffix (normally one
row). Target <=250 ms for one 5,500-event replay batch and <=400 ms for a
1,000-event persisted one-at-a-time pipeline, with canonical equivalence.
**Why higher levels don't apply**: The design removes redundant work at the
highest level; I/O falls as a consequence. Data-locality/runtime/parallelism
work is not justified until this measured redundancy is gone.
**Story**: `feature-app-incremental-transcript-projection-pipeline-opt-3`

#### Implementation Units

##### Unit 3.1: Generation-scoped reducer lifecycle
**File**: `app/lib/data/sync/sync_service.dart`

```dart
Future<void> _appendTranscriptEvents(
  Iterable<TranscriptEvent> events, {
  bool preserveTurnState = false,
});

Future<void> _rebuildTranscriptProjectionForRef(
  RemoteSessionRef ref,
  int generation,
);
```

**Implementation Notes**:
- Own one reducer for the exact active `RemoteSessionRef`; reset it on session
  replacement, clear, and lifecycle generation change.
- Initialize through a clean recovery read during activation. Normal append and
  replay use `AppendTranscriptEventsResult.accepted` only.
- Keep all-duplicate replay recovery explicit so a disposable box can still be
  repaired from an unchanged canonical log.

##### Unit 3.2: Patch only the affected materialized suffix
**File**: `app/lib/data/sync/sync_service.dart`

```dart
Future<void> _applyTranscriptProjectionUpdateInWriteChain(
  RemoteSessionRef ref,
  TranscriptProjectionUpdate update,
  int generation,
);

MessageRecord _recordFromProjectedMessage(
  ChatMessage message,
  DateTime timestamp,
  int sequence,
);
```

**Implementation Notes**:
- Start comparison/write work at `firstChangedMessageIndex`; delete only a
  now-invalid tail and batch changed row puts where Hive permits.
- Preserve generation checks around every await and the turn-projection epoch
  guard before publishing streaming/turn state.
- Reconcile pending timers from changed user rows plus removed tail ownership;
  do not let delta scope leave a stale timer armed.
- Delete `_timestampForProjectedMessage`, append-time `readSession`,
  `_idToSeq`, `_nextSeq`, and their `dart:math` dependency when no caller remains.

**Acceptance Criteria**:
- [ ] Instrumented normal appends make zero `readSession` calls.
- [ ] Each prefix matches a clean rebuild for messages, timestamps, streaming,
      turn, and steering.
- [ ] Session replacement fences stale reducer updates and row writes.
- [ ] Recovery/all-duplicate replay repairs an empty disposable projection.
- [ ] Pending timers and working state converge on existing terminal paths.
- [ ] Benchmark and app unit suite pass.

## Benchmarks

**Location**: `app/benchmark/transcript_projection_pipeline_benchmark_test.dart`

**Run command**:

```bash
cd app
export PUB_CACHE=../.pub-cache
../.tools/flutter/bin/flutter test --no-pub \
  benchmark/transcript_projection_pipeline_benchmark_test.dart \
  --reporter expanded
```

**Baseline targets (rerun)**:

- 5,500 alternating user/assistant projection: 182.262 ms p50 / 198.995 ms p95
  in the localization shape (112.014/121.927 ms in the preceding warm process
  pass; retain the isolated shape as the conservative baseline).
- 5,500 assistant-only: 7.854 ms p50; user-only: 211.875 ms p50.
- 1,000 prefix rebuilds: 1,314.045 ms total p50.
- encrypted Hive 5,500 batch append: 790.356 ms; read: 21.088 ms p50 /
  21.840 ms p95; read+project: 160.594 ms p50 / 168.291 ms p95.
- 1,000 Hive append: 109.623 ms batch / 952.163 ms one at a time.

**Expected targets**:

- 5,500 clean fold <=40 ms p50 / <=60 ms p95.
- 1,000 incremental applies <=100 ms total, oracle excluded.
- 5,500 replay append + incremental materialization <=250 ms.
- 1,000 persisted one-at-a-time pipeline <=400 ms.
- normal accepted-append `readSession` count = 0; affected row writes bounded by
  the returned delta suffix.

**Counter targets**: none. DevTools allocation/CPU profiles and hardware
counters are unavailable/not justified in this host-side high-level Dart lane;
retain RSS as coarse context and prioritize wall latency, call counts, and row
writes.

## Correctness and verification

The optimization is accepted only if the incremental projection equals a clean
full-log rebuild after every generated prefix. Existing soak oracles remain the
end-to-end authority for replay dedupe, message order, session identity,
steering, and working-state convergence. Unit benchmarks are evidence of the
algorithmic win, not proof of mobile lifecycle behavior.

Implementation verification from `app/`:

```bash
../.tools/flutter/bin/flutter analyze
../.tools/flutter/bin/flutter test --exclude-tags e2e --concurrency=2
../.tools/flutter/bin/flutter test --no-pub \
  benchmark/transcript_projection_pipeline_benchmark_test.dart \
  --reporter expanded
```

The implementation pass should rerun the live soak oracle when an emulator/device
lane is available; this host-side design execution intentionally does not claim
that end-to-end validation.

## Implementation Order

1. `feature-app-incremental-transcript-projection-pipeline-opt-1` — establish
   the one canonical reducer and equivalence oracle first.
2. `feature-app-incremental-transcript-projection-pipeline-opt-2` — enrich the
   append boundary and remove repeated sequence/I/O work.
3. `feature-app-incremental-transcript-projection-pipeline-opt-3` — wire both
   contracts into SyncService and delete the old full-rebuild write chain.

## Implementation results

All three optimization checkpoints are complete on the host-side benchmark lane.

- Canonical 5,500-event fold: **172.735 ms p50 / 182.784 ms p95 → 7.657 ms p50 / 15.424 ms p95** (target <=40/60 ms).
- 1,000 one-at-a-time reducer applies: **1,336.309 ms prefix rebuild → 30.997 ms p50 / 37.033 ms p95** (target <=100 ms).
- Encrypted Hive append: 5,500 batch **891.690 → 96.489 ms**; 1,000 batch **116.376 → 16.014 ms**; 1,000 one at a time **964.326 → 215.427 ms** (targets <=250/50/400 ms).
- Receipt-driven pipeline, corrected to the production materialization boundary: the earlier **107.329 ms** 5,500 replay and **258.114 ms** 1,000 one-at-a-time figures stopped after append plus reducer apply and are retained only as the old partial-boundary measurements. The corrected real `SyncService.debugApplyHistory` path, including suffix `MessageRecord` construction, existing-row comparison, deletion, and encrypted `msgs.putAll`, measured **238.706 ms** for the 5,500 replay and **743.216 ms** for 1,000 persisted one-at-a-time events. These extended-boundary numbers replace the old pipeline claims; they are not regressions against the shorter measurement.
- Normal accepted append reads: **1 → 0**; monotonic tail materialization changes one row instead of comparing the full projection.
- Correctness: every generated 200/1,000/5,500 prefix matched a clean canonical rebuild; all 36 projection/store tests, all 102 SyncService tests, and the committed-tree app suite (**934 passed, 1 skipped**) passed. Host-side execution did not claim the emulator/live soak lane.

## Review closure (2026-08-24)

- The benchmark now drives the real `SyncService` history-receipt path against encrypted Hive through completed `msgs` materialization and asserts that the timed append performs no additional full transcript read. This closes the receiver-confirmed partial-boundary finding without copying production materialization logic into the benchmark.
- End-to-end validation did **not** demonstrate a reconnect/hydration improvement at the soak's small transcript scale: the green 300-second post-campaign soak held only 11 final transcript rows, while connecting→online moved from **595.597 ms p50** (n=7) to **685.333 ms p50** (n=10), and online→room snapshot moved from **13.807 ms p50** (n=8) to **16.365 ms p50** (n=11). The 22.6x clean-fold and 43.1x incremental-prefix wins therefore remain validated algorithmic capacity for 5,500-event flood/hydration workloads, not a claimed improvement for this low-volume reconnect sample.
- Closure verification reran the corrected benchmark, the live `state-shapes` selector, a green 300-second soak, clean analyzer, and the full non-e2e app suite (**940 passed**); the epic records the comparable end-to-end table. Device-lane teardown removed `app/build` and left the retained v0.7.2+14 APK byte-identical.

## Review record (2026-08-24)
Standard fresh-context pass over the campaign. Verdict: Request changes →
closed done (f4e382f5, a3ab4fba): pipeline benchmark corrected to the
production materialization boundary (5,500-event replay 238.7ms real
boundary; the earlier 107.3ms claim stopped before materialization);
no incremental/canonical divergence found (rejected finding); reducer
ownership generation-fenced. End-to-end: no soak-scale delta (11 rows);
wins are flood/hydration-scale by design — recorded in the epic.

---
id: feature-app-incremental-transcript-projection-pipeline-opt-2
kind: story
stage: done
tags: [perf]
parent: feature-app-incremental-transcript-projection-pipeline
depends_on: [feature-app-incremental-transcript-projection-pipeline-opt-1]
release_binding: null
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Return accepted append receipts and batch Hive persistence

## Optimization

Make `TranscriptEventStore.appendAll` return the accepted events with their
assigned sequence numbers. `HiveTranscriptEventStore` must derive the next
sequence in constant time from the append-only box shape, preserve first-event
wins for duplicates within a batch, and issue one batched Hive write for a
replay batch. Move session clearing behind the store contract so sequence
ownership and reset behavior cannot drift.

**Hierarchy level:** Algorithmic / data model, then I/O / service boundary.
**Probe families:** storage I/O and workload latency.

## Expected movement

- Delete `_maxSeq(box.values)` from every append: repeated one-event appends no
  longer decode every prior record and sequence assignment moves from `O(n²)`
  cumulative work to `O(n)` across `n` appends.
- Reduce one-at-a-time persistence of 1,000 events from 952.163 ms to <=400 ms.
- Reduce a 1,000-event replay batch from 109.623 ms and the 5,500-event replay
  batch from 790.356 ms to <=50 ms and <=250 ms respectively.
- Give SyncService the exact accepted subset without an append-then-read round
  trip or a second dedupe pass.

## Implementation surface

- `app/lib/domain/contracts/transcript_event_store.dart`
  - add `SequencedTranscriptEvent` (`event`, `sequence`);
  - extend `AppendTranscriptEventsResult` with immutable
    `List<SequencedTranscriptEvent> accepted`;
  - add `Future<void> clearSession(TranscriptSessionKey key)`.
- `app/lib/data/local/transcript_event_store_hive.dart`
  - replace `_maxSeq` with constant-time append-only sequence ownership;
  - collect first-seen accepted records and persist the batch with `putAll`;
  - implement store-owned clear/reset.
- `app/test/data/local/transcript_event_store_hive_test.dart`
  - assert accepted receipt order/sequence, cross-batch monotonicity,
    duplicate-first-wins, clear/reset, restart, and wrong-session rejection.
- `app/test/data/sync/sync_service_test.dart`
  - update the in-memory store fake to return accepted receipts.
- `app/benchmark/transcript_projection_pipeline_benchmark_test.dart`
  - retain the batch versus one-at-a-time BEFORE probes and feed receipt data
    into the second AFTER scaffold.

## Risks and acceptance

- [x] Existing persisted logs reopen in the same order without migration or
      sequence reuse before a full clear.
- [x] Duplicate IDs already stored or repeated inside one batch retain the
      first accepted event and report accurate received/appended/skipped data.
- [x] Store-owned clear resets sequence allocation and keeps lifecycle fencing
      behavior covered by the existing blocked-open/wipe test.
- [x] Benchmarks meet the targets above; normal app tests remain green.

## Implementation

- Execution capability: `sol/high`; storage contract, Hive adapter, fakes, and real encrypted-Hive benchmark.
- Review weight: not applicable — child-story checkpoint.
- Files changed: transcript-store domain contract and Hive adapter, SyncService clear delegation, store/sync fakes, store tests, and benchmark scaffold.
- Tests added: accepted receipt order/sequence, cross-batch allocation, batch-local duplicate-first-wins, clear reset, reopen continuation, and wrong-session rejection coverage.
- Before: 5,500 batch **891.690 ms**; 1,000 batch **116.376 ms**; 1,000 one at a time **964.326 ms**.
- After: 5,500 batch **96.489 ms**; 1,000 batch **16.014 ms**; 1,000 one at a time **215.427 ms**.
- Verification: `flutter analyze --no-pub`, all 12 Hive store tests, all 101 SyncService tests, and the full transcript benchmark passed. The repository-wide suite is temporarily obstructed by concurrent uncommitted room-snapshot work outside this story's write set; focused owned surfaces are green.
- Simplification: removed full-box `_maxSeq` decoding and per-event Hive awaits; clear/reset now belongs to the store contract.
- Discrepancies from design: none.
- Adjacent issues parked: none.

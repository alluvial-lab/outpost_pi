---
id: feature-app-incremental-transcript-projection-pipeline-opt-3
kind: story
stage: done
tags: [perf]
parent: feature-app-incremental-transcript-projection-pipeline
depends_on: [feature-app-incremental-transcript-projection-pipeline-opt-1, feature-app-incremental-transcript-projection-pipeline-opt-2]
release_binding: v0.8.0
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Wire append receipts to delta message materialization

## Optimization

Give each active `RemoteSessionRef` one generation-fenced
`TranscriptProjectionReducer`. Normal appends apply only the accepted receipt
entries and patch the disposable `msgs` box from the reducer's first changed
index. Activation, explicit recovery, and all-duplicate replay recovery remain
the only full `readSession` + rebuild paths.

The reducer's aligned timestamps become the sole source for `MessageRecord.ts`.
Delete append-time full reads, `_timestampForProjectedMessage`, full-row
comparison for unaffected prefixes, and the unused `_idToSeq` / `_nextSeq`
reconstruction. Preserve write-chain ordering, lifecycle generation fences,
turn-projection epochs, pending-send timer reconciliation, and the event log as
truth.

**Hierarchy level:** Algorithmic / data model, with an I/O / service-boundary
payoff.
**Probe families:** on-CPU, storage I/O, workload latency, and coarse RSS.

## Expected movement

- Normal accepted append `readSession` calls: 1 -> 0.
- Timestamp lookup: `O(projected messages × log events)` scans -> 0; timestamps
  travel with the reducer result.
- Disposable-row comparison/writes: every projected row -> affected suffix,
  normally one appended row or one tool/user upsert.
- Move encrypted 5,500-event read+project work from 160.594 ms p50 / 168.291 ms
  p95 to no normal append-path work; keep a 5,500-event replay batch <=250 ms
  end to end and a 1,000-event persisted one-at-a-time pipeline <=400 ms.

## Implementation surface

- `app/lib/data/sync/sync_service.dart`
  - add reducer ownership scoped to `_activeRef` and `_lifecycleGeneration`;
  - change `_appendTranscriptEvents(...)` and `_replayHistory(...)` to consume
    `AppendTranscriptEventsResult.accepted`;
  - add `_rebuildTranscriptProjectionForRef(...)` for activation/recovery;
  - replace `_rewriteMessageProjectionInWriteChain(...)` with
    `_applyTranscriptProjectionUpdateInWriteChain(...)`;
  - remove `_timestampForProjectedMessage`, append-time `readSession`, and
    dead full-index bookkeeping.
- `app/test/data/sync/sync_service_test.dart`
  - count reads and row writes; assert zero normal append reads, bounded changed
    rows, generation fencing, replay dedupe, all-duplicate recovery, and
    pending-timer convergence.
- `app/benchmark/transcript_projection_pipeline_benchmark_test.dart`
  - enable the receipt/delta AFTER scaffold and compare each prefix against a
    clean canonical rebuild outside the timed region.

## Risks and acceptance

- [x] Every incremental prefix equals a clean event-log rebuild for messages,
      timestamps, streaming, turn, and steering state.
- [x] Session replacement/reconnect cannot publish or persist a stale reducer
      update after its generation is invalidated.
- [x] Empty/corrupt disposable projection recovery and all-duplicate replay can
      still rebuild from the canonical log.
- [x] Pending-send timers remain armed/cancelled from the resulting user-row
      status, and working state converges on every existing terminal path.
- [x] The benchmark targets pass and the app unit suite remains green.

## Implementation

- Execution capability: `sol/high`; generation-owned reducer lifecycle, serialized persistence, delta materialization, and async-fence tests.
- Review weight: not applicable — child-story checkpoint.
- Files changed: `app/lib/data/sync/sync_service.dart`, SyncService tests, and the transcript pipeline benchmark.
- Tests added/updated: zero-read/one-row normal append, explicit duplicate-replay recovery, append-gated reconnect race, fail-once recovery read, and existing session replacement/timer/terminal convergence coverage.
- Before: normal accepted append performed one full log read plus clean fold (design baseline **160.594 ms p50 / 168.291 ms p95** at 5,500) and compared every materialized row.
- After: normal accepted append performs **0 `readSession` calls** and tail traffic changes **1 row**; encrypted 5,500 receipt+delta replay is **107.329 ms**, and 1,000 persisted one-at-a-time receipt+delta applies are **258.114 ms**.
- Verification: all 36 projection/store tests, all 102 SyncService tests, `flutter analyze --no-pub`, and the full benchmark passed. The exact repository-wide suite passed from the committed tree: **934 passed, 1 skipped** with `--exclude-tags e2e --concurrency=2`.
- Simplification: deleted append-time full reads, message×event timestamp scans, full-prefix row comparison, `_idToSeq`, `_nextSeq`, and `dart:math`; row writes and pending-timer reconciliation now start at the reducer's affected suffix.
- Discrepancies from design: none.
- Adjacent issues parked: none.

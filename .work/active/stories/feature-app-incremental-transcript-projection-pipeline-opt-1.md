---
id: feature-app-incremental-transcript-projection-pipeline-opt-1
kind: story
stage: implementing
tags: [perf]
parent: feature-app-incremental-transcript-projection-pipeline
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Build the canonical incremental transcript reducer

## Optimization

Replace repeated whole-log derivation with one session-scoped reducer whose
state is updated only by newly accepted events. The same reducer must power
`deriveTranscriptProjection`; full recovery is a fold from an empty reducer,
not a second projection implementation.

The reducer owns event-id dedupe, optimistic/authoritative user state, tool
upserts, streaming/turn/steering state, canonical server-time ordering, stable
arrival tiebreaks, reply anchoring, and a timestamp parallel to every projected
message. `applyAll` returns the first changed message index so infrastructure
can patch only the affected materialized suffix.

**Hierarchy level:** Algorithmic / data model.
**Probe families:** workload baseline, on-CPU time, coarse memory/RSS.

## Expected movement

- Remove the repeated `O(prefixes × events)` full folds and the quadratic
  per-user `indexWhere` reply-anchor pass.
- Move the representative 5,500-event full projection from 182.262 ms p50 /
  198.995 ms p95 in the localized rerun to <=40 ms p50 / <=60 ms p95.
- Move 1,000 one-event-at-a-time reducer applications from 1,314.045 ms total
  to <=100 ms total, excluding the clean-rebuild equivalence oracle.
- Preserve byte-for-byte/value-for-value projection equivalence at every
  generated prefix; the canonical rebuild is the invariant, not the timing.

## Implementation surface

- `app/lib/domain/transcript/transcript_projection.dart`
  - add `TranscriptProjectionReducer.empty({required String sessionId})`;
  - add `TranscriptProjectionUpdate applyAll(Iterable<TranscriptEvent> events)`;
  - add aligned projected-message timestamps and
    `int? firstChangedMessageIndex` to the update contract;
  - implement `deriveTranscriptProjection(...)` by folding this reducer.
- `app/test/domain/transcript/transcript_projection_test.dart`
  - exercise all event variants, duplicates, backfill, same-time reply anchors,
    optimistic tails, tool upserts, steering, and terminal convergence through
    both incremental and clean-rebuild paths.
- `app/benchmark/transcript_projection_pipeline_benchmark_test.dart`
  - enable the first AFTER scaffold and time reducer work separately from its
    prefix-by-prefix clean-rebuild oracle.

## Risks and acceptance

- [ ] Incremental output equals a clean `deriveTranscriptProjection` rebuild
      after every prefix of the 200-, 1,000-, and 5,500-event fixtures.
- [ ] Deterministic replay dedupe, canonical server-time ordering, stable
      arrival ties, reply anchoring, optimistic tails, tool replacement,
      streaming, steering, and turn convergence remain unchanged.
- [ ] The benchmark reaches the targets above without weakening correctness
      assertions or timing the oracle as reducer work.
- [ ] Existing transcript projection tests pass.

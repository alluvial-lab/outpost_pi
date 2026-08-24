---
id: feature-app-incremental-transcript-projection-pipeline
kind: feature
stage: drafting
tags: [perf, app]
parent: epic-perf-optimization-campaign
depends_on: []
release_binding: null
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
`app/lib/data/local/transcript_event_store_hive.dart`. Every accepted append
can scan the event box for sequence, append, read and decode the complete log,
rederive the complete projection, rescan the log once per projected message for
timestamps, and compare/rewrite the disposable message projection. Pure
projection p50 rose from **0.690 ms at 200 events** to **5.577 ms at 1,000** and
**198.813 ms at 5,500** (p95 211.371 ms); rebuilding after every prefix append
took **1,330.628 ms total for only 1,000 events**. The actual encrypted Hive
store took **859.471 ms to batch-append 5,500 events** and a full read took
**20.755 ms p50 / 34.014 ms p95**. Proposed hierarchy level:
**Algorithmic / data model**, then **I/O / service boundary**, with **workload,
on-CPU, memory, and storage-I/O** probes.

## Optimization direction for the design pass

Design a canonical incremental reducer/materialization boundary: accepted new
events should update event identity, ordering metadata, turn/steering state,
and affected message rows once. Full-log rebuild remains the explicit
activation/recovery path, not the default append path. The event-store append
result should carry enough accepted-event/sequence information to avoid an
append-then-`readSession` round trip, and sequence ownership should not rescan
all records on every append.

This is not a memoization cache. The existing `msgs` box is already a disposable
materialized projection; the design pass should make that projection's update
model explicit while preserving the append-only event log as truth and a
full-rebuild equivalence oracle.

## Simplification opportunity

Target deletion of the append-time full `readSession`, the per-message
`_timestampForProjectedMessage` log scan, full-row comparison loops for
unaffected messages, and `_maxSeq(box.values)` on each append. A single reducer
contract should replace the overlapping event-log, message-timestamp, and
message-row traversals.

## Discovery constraints for perf-design

- Preserve deterministic replay dedupe, canonical server-time ordering,
  same-timestamp reply anchoring, optimistic local tails, tool upserts,
  steering state, session fencing, and full recovery from an empty/corrupt
  disposable projection.
- Scaffold before/after benchmarks for 200, 1,000, and 5,500 events; include
  both one replay batch and one-event-at-a-time append shapes.
- Validate the chosen incremental result against a clean full rebuild for every
  generated event prefix; microbench improvement alone is not proof.
- Record allocations/RSS or VM allocation evidence when the implementable
  headless tooling permits it.

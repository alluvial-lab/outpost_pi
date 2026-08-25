---
id: gate-tests-projection-adversarial-equivalence
kind: story
stage: done
tags: [testing, app, perf]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: tests
created: 2026-08-25
updated: 2026-08-25
---

# Pin incremental projection equivalence under adversarial event histories

## Priority
High

## Value evidence
Item: `feature-app-incremental-transcript-projection-pipeline`. Its correctness
contract is that incremental application equals a clean fold for every accepted
history, especially middle insertions and affected-suffix rewrites. The
functional oracle uses one hand-ordered example of each event variant
(`app/test/domain/transcript/transcript_projection_test.dart:655`), while the
5,500-event benchmark uses only monotonic alternating user/assistant events
(`app/benchmark/transcript_projection_pipeline_benchmark_test.dart:198`). Neither
exercises the partitions that forced an affected-suffix design: shuffled server
timestamps, late confirmations, duplicate event/message ids, results before
requests, repeated reply targets, mixed steering/compaction/error facts, foreign
sessions, or irregular batch boundaries.

## Gap type
complex-unit / equivalence partitions / state-transition ordering

## Suggested test
```dart
// Deterministically generate seeded valid histories from the adversarial
// partitions above. Apply each history as: one clean batch, one event at a
// time, and irregular batches. After every accepted prefix compare messages,
// timestamps, streaming, turn, steering, and firstChangedMessageIndex's
// materialized suffix against a clean fold. Persist selected cases through the
// real Hive receipt/materialization seam and reopen before the final compare.
// Print the seed on failure; do not use elapsed-time sleeps.
```

## Test location (suggested)
`app/test/domain/transcript/transcript_projection_test.dart` and `app/test/data/sync/sync_service_test.dart`

## Implementation

Added deterministic adversarial histories for seeds `7`, `42`, and `8080`.
Each history covers shuffled canonical timestamps, late confirmations,
duplicate event and message identities, tool results before requests, repeated
reply targets, steering acceptance/pickup, streaming, terminal errors, repeated
compaction facts, and foreign-session input. Each seed is applied as one batch,
one event at a time, and seeded irregular batches. Every partition boundary
compares messages, timestamps, streaming, turn, steering, the reported first
changed row, and the affected materialized suffix against a clean fold; failure
reasons print the seed and partition.

The pins-contract test exposed a real defect before the production change:
`result-before-request retains terminal tool outcome and request metadata`
failed because the later request replaced the completed result with `pending`
and retained empty tool args. The minimal reducer fix now merges late request
metadata into an already-terminal tool row while preserving its outcome.

Verification:

- Fails-before evidence: focused test reported `args: {}` (and the old reducer
  would also replace the terminal status) for the result-before-request case.
- `flutter test test/domain/transcript/transcript_projection_test.dart --concurrency=2` (26 passed)

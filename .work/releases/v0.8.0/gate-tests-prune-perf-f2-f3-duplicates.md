---
id: gate-tests-prune-perf-f2-f3-duplicates
kind: story
stage: done
tags: [testing, refactor, app, pi-extension]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: tests
created: 2026-08-25
updated: 2026-08-25
---

# Remove obsolete benchmark baselines and duplicated F2/F3 producer coverage

## Priority
Low

## Value evidence
Items: `epic-perf-optimization-campaign`,
`feature-canonical-transcript-timestamp-ownership`, and
`epic-durable-transcript-ownership-durable-native-events`. The four `BEFORE:`
tests in `app/benchmark/transcript_projection_pipeline_benchmark_test.dart:27-197`
now call the optimized production functions; the removed implementation no
longer exists, so they cannot reproduce a before baseline and mostly assert
list lengths while adding large workload cost. In the parallel F2/F3 waves,
`tool_execution_start → tool_request emitted via channel` (`pi-extension/src/extension.test.ts:3662`) is a subset of `start → end pair...` (`:3836`), which
itself overlaps the stronger execution-authority/session-history test at
`:6664`. Keeping all three repeats expensive extension setup without protecting
three distinct contracts.

## Gap type
low-value-test-removal

## Suggested test
```text
Delete the four misleading BEFORE runtime tests; retain historical baseline
numbers as fixture metadata/report context only. Consolidate the three tool
producer tests into one producer-connected test that preserves the unique
assertions: owner routing, request/result order, persistence-before-broadcast,
live/history timestamp equality, and SDK tool-message non-authority. Keep the
pure reconciler and real-file reopen tests because they protect different
boundaries. Compare runtime and mutation sensitivity before/after pruning.
```

## Test location (suggested)
`app/benchmark/transcript_projection_pipeline_benchmark_test.dart` and `pi-extension/src/extension.test.ts`

## Implementation

Removed the four `BEFORE:` runtime cases. They invoked the same optimized
`deriveTranscriptProjection`/Hive adapters as the retained `AFTER:` cases, so
none could reproduce the deleted baseline implementation; their unique output
was historical timing labels plus weak length assertions. The benchmark now
runs three production-path cases instead of seven while retaining clean-fold,
incremental-prefix equivalence, batched receipt, and real Hive materialization
coverage.

Proved the F2/F3 redundancy before deletion by comparing assertions: the
request-only case was a strict subset of the start/end pair, and that pair was
a subset of the execution-authority history case. Consolidated their unique
claims into the authority case: owner routing, request/result order, durable
append before the observed live pair, live/durable/history timestamp equality,
and SDK `toolResult` non-authority. The focused extension file now runs 214
cases instead of 216 without losing a distinct producer contract.

Verification:

- `flutter test benchmark/transcript_projection_pipeline_benchmark_test.dart --concurrency=2` (3 passed)
- `corepack pnpm exec vitest run src/extension.test.ts` (214 passed)

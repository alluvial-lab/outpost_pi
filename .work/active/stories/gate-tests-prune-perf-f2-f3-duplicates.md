---
id: gate-tests-prune-perf-f2-f3-duplicates
kind: story
stage: implementing
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

---
id: gate-tests-perf-regressions-fail-default-suite
kind: story
stage: implementing
tags: [testing, app, perf]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: tests
created: 2026-08-25
updated: 2026-08-25
---

# Make the v0.8.0 performance contracts fail a routine verification lane

## Priority
High

## Value evidence
Items: `epic-perf-optimization-campaign`,
`feature-app-incremental-transcript-projection-pipeline`, and
`feature-app-edge-trigger-room-snapshot-consumers`. The headline projection
thresholds exist only under `app/benchmark/`, which the routine
`flutter test --exclude-tags e2e` suite does not discover, and no workflow
invokes that file. The room benchmark protects call counts but prints wall
p50/p95 without any regression threshold
(`app/test/perf/room_snapshot_consumers_benchmark_test.dart:538-563`). A future
CPU/materialization regression can therefore leave the normal 946-test lane
green. The release's 22×/43× and 339→0 claims need one stable regression lane,
not measurements that pass unless an operator remembers a separate command.

## Gap type
important-interface / performance regression detection

## Suggested test
```dart
// Put stable structural budgets (readSession calls, affected-row writes,
// binding refreshes, snapshot writes) in the default test/perf lane. Add a
// separately invoked benchmark job for host-sensitive latency budgets with
// warmup, several samples, generous calibrated ceilings, and PERF_JSON output.
// Prove the gate has teeth by temporarily restoring one removed whole-log read
// or full-prefix rebuild and showing the appropriate lane fails.
```

## Test location (suggested)
`app/test/perf/`, `app/benchmark/transcript_projection_pipeline_benchmark_test.dart`, and the repository CI workflow

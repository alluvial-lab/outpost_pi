---
id: gate-tests-perf-regressions-fail-default-suite
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

## Implementation

Added the runnable host-side lane:

```bash
scripts/run_app_perf_regressions.sh
```

The app CI job invokes that command after the default non-E2E suite, and app
path filtering includes the lane script itself. Every probe emits valid
`PERF_JSON` and fails its Flutter test process when its budget is exceeded:

- existing debug-ring admission/coalescing benchmark: 5,500 events after
  encoder warmup, wall ≤ **75 ms**;
- transcript clean fold: 5,500 events, p50 ≤ **15 ms**;
- room-snapshot consumer fan-out: 339 snapshots at 0/200/5,500 transcript
  events, p95 ≤ **200 µs** per snapshot.

The ring budget deliberately follows the campaign's recorded **43.9 ms**
(7.99 µs/event) with shared-runner headroom; the full concurrent suite measured
52.736 ms. A 10 ms budget would be below the measured production JSON-encoding
path and would make the lane permanently red rather than detecting regression. Structural budgets remain in
the default `test/perf` lane: zero transcript reads, zero binding refreshes,
zero anchor callbacks, and no-op snapshot notification stability.

The assertions provide the failure boundary: restoring the removed whole-log
room read, full-prefix projection fold, or pre-optimization ring recount would
exceed respectively the structural zero, 15 ms fold, or 55 ms admission
budget and make the script exit non-zero. No product defect was found.

Verification:

- `scripts/run_app_perf_regressions.sh` passed.
- Recorded this host run: existing ring benchmark 52.736 ms in the full suite;
  clean fold p50 8.315 ms; fan-out p95 71/50/52 µs for 0/200/5,500 events.

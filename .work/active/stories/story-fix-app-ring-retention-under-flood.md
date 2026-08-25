---
id: story-fix-app-ring-retention-under-flood
kind: story
stage: done
tags: [bug, app]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Preserve newest debug-ring rows during flood export

## Symptom

`e2e/run-live.sh state-shapes` failed in `live_device_harness.dart` after a 5,500-event `wsIn` flood: the oldest marker rotated out as expected, but the immediately captured export did not contain the newest row (`count == 5499`). The failure began after commit `668cbcee`, which introduced constant-time ring admission and coalesced flushing.

## Root cause

This was read-path mismatch **(b)**, not FIFO byte-cap ordering (a) or dropped flush chunks (c). `export()` awaited its own force-flush and then streamed the canonical jsonl file, but a live critical event could start another flush between those operations. Snapshot replacement used `File.writeAsString`, which truncates the canonical file before filling it. The export reader could therefore observe the concurrent writer's empty truncate/write window and return `null` (observed live as zero captured rows) even though the bounded in-memory ring still held the newest flood row.

## Fix approach

Keep the FIFO queue, incremental byte accounting, and dirty-latched coalesced drain unchanged. Write each complete snapshot to a per-logger temporary sibling file, flush it, then atomically rename it over the canonical jsonl file. Export consequently sees either the prior complete snapshot or the next complete snapshot, never an empty/partial replacement window.

## Regression test

`app/test/data/debug/debug_log_impl_test.dart` floods the production-size ring with the state-shapes event shape, performs the harness's export-then-capture sequence, and uses explicit barriers to start a critical snapshot commit while the second export is about to read. It asserts that the oldest marker is absent and `count == 5499` remains present.

Fails-before evidence:

```text
Expected: not null
  Actual: <null>
test/data/debug/debug_log_impl_test.dart 241:7
```

The original device reproduction also failed at `live_device_harness.dart:740` with `Expected: true / Actual: <false>`; an instrumented diagnosis run confirmed the failing second capture decoded zero rows.

## Implementation notes

- **Execution capability:** `openai-codex/gpt-5.6-sol` at high reasoning, selected because the narrow fix depended on diagnosing an async file-read/write interleaving across unit and live-device paths.
- **Files changed:** `app/lib/data/debug/debug_log_impl.dart` and `app/test/data/debug/debug_log_impl_test.dart`.
- **Regression confirmation:** the deterministic export/read interleaving failed before the fix with `Expected: not null / Actual: <null>` and passed after atomic snapshot replacement.
- **Ring verification:** `flutter test test/data/debug/debug_log_impl_test.dart` passed 20 tests.
- **Full verification:** `flutter analyze` reported no issues; `flutter test --exclude-tags e2e --concurrency=2` passed 938 tests.
- **Performance:** checked-in benchmark reported 5,500 admissions in `43,963 us` (`7.99 us/event`), one coalesced critical snapshot write, retaining the constant-time admission win.
- **Original reproduction:** `e2e/run-live.sh state-shapes` passed all 3 tests plus capture after the fix.
- **Soak:** `python3 e2e/live_soak.py --duration 300 --seed 2026082401` exited 0; 11 checkpoints and all replay-dedup, transcript-projection, ordering, and identity oracles passed, with anomalies reconciled to scheduled faults.
- **Lane hygiene:** emulator and live Docker stack are down; `app/build/` was removed; retained `.work/artifacts/app-0.7.2+14-debug.apk` remained byte-identical (SHA-256 `b366eee5ef6db0e959a9b33297637fed7281646cabea1e5d113530e0f6ae655f`).
- **Adjacent issues parked:** none.

## Bounded inline review

- **Mode:** standalone-story bounded inline review; no independent, fresh-context, or cross-model reviewer ran.
- **Verdict:** **Approve**.
- **Passes:** 1.
- **Lenses:** root-cause alignment, FIFO/cap preservation, async file-I/O ordering, failure containment, diagnostic privacy, regression-test integrity, performance, and lane hygiene.
- **Findings:** no blockers, important findings, or nits. The sibling-temp write and same-directory rename remove only the observable truncate window; queue admission, eviction order, byte accounting, coalescing, export filtering, and the 1 MiB cap remain unchanged.
- **Closure reason:** the deterministic regression passes, full app verification and the original live selector are green, the 5-minute seeded soak is green, and the benchmark remains within the requested O(1)-ish budget.

## Closure appendix — warm-load chronology and stale temporary snapshots

The follow-up review found two additional correctness gaps in the rewritten ring and closed them in the same campaign:

- **I1 — warm-load chronology inversion:** `log()` now buffers admissions while the shared asynchronous load is in flight. File rows are appended first, then buffered live rows are merged in call order. Once loading completes, the steady-state path remains synchronous and O(1)-amortized; it does not await I/O per event.
- **N1 — crash-orphaned temporary snapshots:** load completion sweeps sibling `outpost_pi_debug.jsonl.tmp.*` files unless the exact path is currently owned by an active in-process snapshot write. Cleanup is best-effort and cannot fail loading.

### Regression evidence

- I1 fails before the fix: a near-full warm file exports only `old-last`; the concurrent `new-event` is evicted because it was admitted before the older file rows.
- N1 fails before the fix: a stale `outpost_pi_debug.jsonl.tmp.crashed-writer` remains after warm load (`Expected: false / Actual: true`).
- After the fix, both deterministic tests pass. The debug-ring suite passes 22 tests.

### Verification

- Benchmark: 5,500 admissions in `43,958 us` (`7.99 us/event`), retaining the requested approximately-50ms flood budget; the critical burst used one coalesced snapshot write.
- Full app suite: `flutter test --exclude-tags e2e --concurrency=2` passed 940 tests.
- `flutter analyze` remains blocked only by two pre-existing `invalid_use_of_visible_for_testing_member` warnings in the unrelated `app/benchmark/transcript_projection_pipeline_benchmark_test.dart` worktree change.
- No version bump and no push.

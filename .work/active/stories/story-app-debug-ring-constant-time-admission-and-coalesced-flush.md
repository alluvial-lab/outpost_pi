---
id: story-app-debug-ring-constant-time-admission-and-coalesced-flush
kind: story
stage: done
tags: [perf, app]
parent: epic-perf-optimization-campaign
depends_on: []
release_binding: v0.8.0
gate_origin: perf-design
created: 2026-08-24
updated: 2026-08-24
---

# Make debug-ring admission constant-time and coalesce snapshot flushes

## Brief

Bottleneck: `app/lib/data/debug/debug_log_impl.dart` — `DebugLogImpl.log`,
`_truncate`, and `_flushNow`. The enabled per-frame `wsIn` path recomputes the
UTF-8 size of the entire retained ring on every append, and critical events
queue one full-ring snapshot rewrite each. On Dart 3.12.2/Linux, the real
implementation took **4,448.655 ms for 5,500 `wsIn` events (808.85 us/event)**
versus **0.171 us/event disabled**; the resulting ring was 609,377 bytes. After
that prefill, 339 immediate-flush `roomSnapshot` events took **656.027 ms to
log/enqueue plus 2,510.100 ms to drain** a chain that repeatedly rewrote the
646,844-byte snapshot. Proposed hierarchy level: **Algorithmic / data model**
with **on-CPU, memory, and I/O/serialization** probes.

## Optimization direction

- Maintain retained UTF-8 byte count incrementally and use a FIFO whose oldest
  removal does not shift the full list. Preserve the exact 1 MiB and
  newline-accounting contract.
- Coalesce overlapping critical flush requests. A dirty/trailing-flush latch
  must guarantee that an event arriving after an in-flight snapshot began is
  covered by at most one follow-up write, rather than adding another write for
  every critical event.
- Preserve immediate critical-event durability, ordered snapshots,
  `clear()` serialization, warm-from-file behavior, forbidden-key filtering,
  and the never-throw boundary.

## Simplification opportunity

Delete the whole-ring `fold` and repeated UTF-8 re-encoding from every append,
`List.removeAt(0)` shifting, and the unbounded one-full-snapshot-per-critical-
event flush chain. This is not a cache: byte ownership and dirty state become
part of the ring data structure itself.

## Acceptance criteria

- [x] A checked-in benchmark derived from the discovery workload covers 200 and
      5,500 `wsIn` events plus 339 critical events after a ~609 KiB prefill.
- [x] The 5,500-event enabled workload improves by at least 5x on the same VM,
      without weakening the byte cap or debug-enabled gate.
- [x] A burst of 339 critical events causes bounded/coalesced snapshot writes
      while the final on-disk snapshot contains the last event.
- [x] Existing crash-tail, clear-vs-flush, ordering, export, corruption, privacy,
      and lifecycle tests remain green.

## Implementation

- Replaced the shifting `List<String>` ring with a FIFO `Queue` of encoded lines
  carrying their UTF-8-plus-newline byte ownership. Admission now encodes and
  counts only the new row, and oldest-line eviction uses `removeFirst()` while
  maintaining the retained total incrementally.
- Replaced the per-request future chain with one dirty-latched flush drain. A
  request that overlaps a captured/in-flight snapshot causes at most one
  trailing snapshot; synchronous critical bursts collapse into one write.
- Kept `clear()` on the same serialization boundary: it waits until the active
  drain is stable, publishes a clear barrier during the empty-file write, and
  lets post-clear admissions flush only after that barrier. Tests use explicit
  started/release completers rather than elapsed-time sleeps.
- Preserved the existing encoded debug-row shapes and forbidden-key handling;
  `wsIn` and `replayDedup` triage fields are unchanged.

### Benchmark

Command (from `app/`):

```text
flutter test --no-pub test/perf/debug_log_benchmark_test.dart --reporter expanded
```

Same Linux VM and 5,500-event Dart-test timing pattern as discovery. The
checked-in workload retains 609,390 bytes before the critical burst.

| Probe | Before (discovery) | After | Change |
|---|---:|---:|---:|
| 200-event admission | 11,398 us | 6,253 us | 1.82x faster |
| 5,500-event admission | 4,448,655 us (808.85 us/event) | 43,405 us (7.89 us/event) | **102.49x faster** |
| 339 critical-event enqueue | 656,027 us | 2,148 us | 305.41x faster |
| critical drain | 2,510,100 us across 339 writes | 7,317 us across 1 coalesced write | 343.05x faster |

The final file was 649,112 bytes and its final row was the 339th
`roomSnapshot` event (`presenceCount: 338`). The benchmark enforces the locked
5x floor, the ~609 KiB prefill, no more than two overlapping writes, and final
row durability.

### Verification

- Focused debug adapter + performance tests: 20 passed.
- Full committed app analyzer surface: no issues (explicit paths excluded only
  an unrelated concurrently-written, untracked benchmark).
- Full committed app test surface: passed with `--exclude-tags e2e
  --concurrency=2` (930 tests; benchmark included; same untracked benchmark
  excluded).
- `scripts/debug_capture_triage.py --selftest`: all 10 parser/oracle checks
  passed. The discovery capture still parsed all 294 rows with zero malformed
  rows, including 87 `wsIn` and 110 `replayDedup` rows; it reports its known
  reconnect-churn anomaly by design.
- Adjacent issues parked: none.

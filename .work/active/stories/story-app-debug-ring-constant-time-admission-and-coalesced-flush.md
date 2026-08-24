---
id: story-app-debug-ring-constant-time-admission-and-coalesced-flush
kind: story
stage: implementing
tags: [perf, app]
parent: epic-perf-optimization-campaign
depends_on: []
release_binding: null
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

- [ ] A checked-in benchmark derived from the discovery workload covers 200 and
      5,500 `wsIn` events plus 339 critical events after a ~609 KiB prefill.
- [ ] The 5,500-event enabled workload improves by at least 5x on the same VM,
      without weakening the byte cap or debug-enabled gate.
- [ ] A burst of 339 critical events causes bounded/coalesced snapshot writes
      while the final on-disk snapshot contains the last event.
- [ ] Existing crash-tail, clear-vs-flush, ordering, export, corruption, privacy,
      and lifecycle tests remain green.

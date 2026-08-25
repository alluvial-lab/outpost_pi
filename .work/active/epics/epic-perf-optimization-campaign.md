---
id: epic-perf-optimization-campaign
kind: epic
stage: done
tags: [perf]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Performance and optimization campaign (v0.8.0 arc)

## Brief

Operator commission (2026-08-24, post-v0.7.0): "issue a performance and
optimization campaign for the next version bump," motivated by the
reconnect/reliability arena — where every fix this arc landed, performance
work is the complementary piece (faster hydration, faster convergence,
lower per-frame overhead = fewer windows for the remaining timing bugs to
bite).

The campaign covers the three runtime components — **app** (Flutter
mobile), **pi-extension** (Node/TS), **relay** (Rust) — with the mobile
session path (transcript hydration, projection rebuild, reconnect,
per-frame logging) as the priority lane. Cockpit/site are out of scope
unless discovery surfaces something dramatic.

Method (locked): **perf-design discovery first** — profile the top entry
points under realistic load, emit one item per measured bottleneck with
hierarchy level + probe family + evidence (`gate_origin: perf-design`) —
then per-feature design passes for multi-site items. No intuition-driven
optimization; no caching as band-aid.

## Strategic decisions

- **Breadth**: whole-runtime-component discovery, mobile-first priority
  ordering — the arena that motivated the campaign gets first claim on
  implementation order.
- **Method**: measured discovery (perf-design) over speculative
  brainstorming (perf-scout); scout-style ideas that surface during
  profiling get parked, not promoted.
- **Relationship to the hedge fix**: `story-fix-app-reconnect-hedge-…` is
  correctness work that stays standalone; its latency outcomes (reconnect
  time) inform the campaign's baseline but are not campaign items.
- **Workload realism**: the e2e compose stack + live soak are the load
  generators (they exercise production paths end-to-end); microbenchmarks
  only for isolated algorithmic comparisons, always validated against the
  end-to-end numbers.
- **Version frame**: targets v0.8.0 (next bump after v0.7.0).

## Success metrics (to be baselined by discovery)

- App: reconnect→hydrated→interactive time; cold-open to first frame;
  transcript projection rebuild cost per insert (the 5500-event soak
  flood is the stress workload); debug-ring overhead per ws frame.
- Extension: ingress handling cost per envelope; replay-queue drain time.
- Relay: forward-path p99 under soak load; auth path cost.

## Simplification opportunity

Performance work regularly deletes code (redundant projections,
per-frame allocations, double serialization). Each emitted item records
what it can delete, not just what it can speed up.

## Discovery summary

Discovery profiled five capped entry points on 2026-08-24 (Linux, 8 vCPU,
16 GiB; Dart 3.12.2, Node 24.18/24.19, Rust 1.94):

1. **App transcript append/materialization.** The top bottleneck is repeated
   whole-log and whole-projection work. Pure projection p50 was 0.690 ms at 200
   events, 5.577 ms at 1,000, and **198.813 ms at 5,500** (p95 211.371 ms;
   5,500 projected messages; the discovery harness's derived message-count
   label undercounted its alternating user/assistant fixture). Rebuilding every
   prefix through 1,000 one-at-a-time appends
   took **1,330.628 ms**. The real encrypted Hive store batch-appended 5,500 in
   859.471 ms and read the full log in 20.755 ms p50 / 34.014 ms p95.
2. **App per-frame debug ring.** The top bottleneck is `_truncate`'s full-ring
   byte recount plus one full snapshot write queued per critical event. Logging
   5,500 enabled `wsIn` events took **4,448.655 ms (808.85 us/event)** versus
   0.171 us/event disabled and retained 609,377 bytes. After that prefill, 339
   immediate-flush room snapshots took 656.027 ms to enqueue and 2,510.100 ms
   to drain the redundant snapshot-write chain.
3. **App room/chat snapshot fan-out.** The partial soak observed 10 room
   snapshots in 159 seconds; the motivating capture had 339/11h. A bound live
   room unconditionally reaches a full transcript read for held-send replay,
   measured at **20.755 ms p50** for 5,500 events, even when no held send exists;
   ChatViewModel also performs duplicate binding/recompute work. The transcript
   anchor callback itself is gated by transcript/streaming change and was not
   the room-only bottleneck.
4. **Extension owner ingress/replay.** A 360-byte bounded outer ingress plus
   client-message validation measured **2.315 us p50 / 2.490 us p95** (about
   431,911 envelopes/s). The actual e2e Pi-host V8 profile covered 342.709 s and
   was **99.28% idle**; project source accounted for 203 of 1,043,699 self
   samples (about 50.8 ms sampled CPU). The two-entry replacement replay queue
   did not activate, so drain latency remains explicitly unbaselined; no
   extension bottleneck item was emitted.
5. **Relay forward/auth.** Release-mode loopback outer forwarding measured p99
   **0.1459 ms** for one pair/10,000 frames and **0.3456 ms** for four concurrent
   pairs/20,000 frames (26,857 frames/s). Auth handshake through the first
   authenticated control reply was **2.212 ms p99** (n=150); isolated Ed25519
   verify was 29.591 us p50 and typed outer decode 531 ns p50. No relay item was
   justified.

Emitted bottleneck items:

- `story-app-debug-ring-constant-time-admission-and-coalesced-flush`
  (`story`, `implementing`) — algorithmic/data-model + I/O/serialization.
- `feature-app-incremental-transcript-projection-pipeline`
  (`feature`, `drafting`, `[perf]`) — algorithmic/data-model, then I/O boundary.
- `feature-app-edge-trigger-room-snapshot-consumers`
  (`feature`, `drafting`, `[perf]`) — algorithmic/data-model + I/O/UI fan-out.

Success-metric baselines from the realistic lane and isolated probes:

- Reconnect connecting→online: n=7, p50 **595.597 ms**, p95/max 680.222 ms.
- Online→authoritative room snapshot: n=8, p50 **13.807 ms**, p95/max
  184.485 ms; online→first route event p50 3.031 ms.
- Initial captured pre-auth frame→first room snapshot: **1,928.121 ms**;
  →first projection materialization: **1,960.060 ms**. The harness exposes no
  process-launch→Flutter-first-frame timestamp, so these are the nearest cold
  bootstrap baselines rather than a claim about first rendered frame.
- Transcript projection, debug-ring, extension ingress, relay forward p99, and
  auth baselines are the figures above.
- The requested 180-second soak reached 159 seconds before the existing
  timeout-fault recovery lane failed in `StatusNoPeer` with no session. It still
  captured 294 rows and green replay/projection/order/identity oracles through
  its completed checkpoints; treat its latency data as a partial baseline, not
  a green acceptance run.

Skipped high-value probes: Dart DevTools exists but the device integration lane
exposes no stable VM-service URI for headless CPU/allocation attachment; coarse
process RSS and Stopwatch probes were used instead. `perf` is not installed and
`perf_event_paranoid=3`, so Rust hardware-counter/cache/branch evidence was
unavailable; the relay was not CPU-bound at the measured throughput/p99. The
crate has no Criterion or `[[bench]]` target, so discovery used a temporary
release-mode batch harness. Each proposed fix records code it can delete; none
uses caching as a band-aid.

<!-- Children emitted by perf-design discovery; epic-design decomposition
follows if discovery reveals feature-scale arcs. -->

## End-to-end validation

Review closure reran the locked realistic lanes on 2026-08-24. The standalone
`state-shapes` command was green: **176.180 s total command wall** including
compose startup, two APK builds, emulator boot/install, tests, capture, and
cleanup; Flutter's device-test phase was **34 s**. The comparable historical
selector phase was about **47 s** before the ring work and about **31 s** in the
recent post-work run, so the current 34-second result remains about **13 s /
27.7% faster** than the pre-ring run while showing roughly 3 seconds of normal
run-to-run spread. The newly printed 5,500-event flood phase took **99 ms** in
the standalone selector.

The 300-second soak (seed `2026082401`) was green in **5:04** device-test wall.
Its capture contained 714 rows, 18 room snapshots, 10 hydration events, and 11
final transcript rows; replay-dedup, DB↔ViewModel projection, rendered-bubble,
canonical-ordering, and owner/channel-identity oracles all passed. Scheduled
fault churn was reconciled with no outside-window cluster.

The reconnect distributions use the exact discovery method: pair each
`connStatus: connecting` with its next `connStatus: online`, then each online
sample with the next `roomSnapshot` capture timestamp.

| End-to-end interval | Discovery | Post-campaign 300 s soak | Observed movement |
|---|---:|---:|---:|
| Connecting→online | n=7, p50 **595.597 ms**, p95/max **680.222 ms** | n=10, p50 **685.333 ms**, p95/max **871.528 ms** | **+89.736 ms p50**; no measured improvement |
| Online→authoritative room snapshot | n=8, p50 **13.807 ms**, p95/max **184.485 ms** | n=11, p50 **16.365 ms**, p95/max **188.986 ms** | **+2.558 ms p50**; no measured improvement |

| Headline microbenchmark win | Measured end-to-end result | Honest conclusion |
|---|---|---|
| Debug-ring 5,500-event admission: **102.49x** | Comparable selector phase **~47 s → 34 s**; current 5,500-event flood **99 ms** | Visible end-to-end improvement in the ring-heavy state-shape lane. The full command wall is dominated by build/emulator setup, so only selector-phase walls are compared. |
| Transcript pipeline: clean fold **22.6x**, 1,000 incremental prefixes **43.1x** | Connecting→online and online→snapshot p50s did not improve in the 11-row soak. The corrected materialization-boundary host probe is **238.706 ms** for 5,500 replay and **743.216 ms** for 1,000 one-at-a-time events; the old **107.329/258.114 ms** figures ended before materialization and are not used as pipeline claims. | No end-to-end effect demonstrated at this transcript size. The win matters during 5,500-event transcript flood/hydration or sustained append workloads, where projection and suffix materialization are material rather than hidden by network/fault timing. |
| Room-snapshot fan-out: **339 → 0** full reads | The soak emitted only **18** snapshots over 11 rows, and online→snapshot p50 was slightly slower. | No end-to-end effect demonstrated at this scale. Avoided reads become material for long-lived rooms approaching the 339-snapshot/5,500-event workload; invisible here does not mean the removed repeated I/O is wasted. |

### Review-closure verification

- Corrected materialization-boundary benchmark: green; production
  `SyncService.debugApplyHistory` path reaches suffix construction,
  existing-row comparison, deletion, and encrypted `msgs.putAll` with no
  append-time full transcript read.
- `e2e/run-live.sh state-shapes`: green, 3/3 scenarios, 34-second device-test
  phase, 99 ms flood, 176.180-second full command wall.
- `python3 e2e/live_soak.py --duration 300 --seed 2026082401`: green, all soak
  invariants passed.
- App analyzer was clean and the full non-e2e suite passed **940 tests** after
  the benchmark/harness changes. Device-lane cleanup left no emulator or live
  compose stack, removed generated `app/build`, and preserved the retained
  v0.7.2+14 APK byte-for-byte. No version bump was made.


## Campaign close (2026-08-24)

Standard review over the full arc; blockers (benchmark boundary +
end-to-end method) closed in f4e382f5/a3ab4fba. Consolidated results
(discovery baseline → landed):

| Work | Baseline | Result | End-to-end |
|---|---|---|---|
| Debug ring admission+flush | 809µs/event; 3.2s critical flushes | 7.99µs/event (102×); 339→1 writes | selector 47s→34s; flood phase 99ms |
| Projection pipeline fold/incremental | 173ms / 1,336ms | 7.7ms / 31ms (22×/43×) | no soak-scale delta; flood/hydration scale |
| Materialization-boundary pipeline (true) | — | 238.7ms @5,500 replay | (corrected boundary, f4e382f5) |
| Snapshot fan-out reads | 339 reads ≈7.04s p50/339 snaps | 0 reads; 29-41µs/snapshot | no 18-snapshot-scale delta; long-session scale |
| Reconnect hedge (sibling fix) | ~30s stalls; supersede churn | 0.8-3.7s recoveries; zero supersede | soak-verified |

Also landed: ring retention regression fix (34543ad0, atomic rename),
warm-load chronology + tmp sweep (a3ab4fba), hedge fix c1969a45.
Baselines for the next round: connect→online p50 685ms; online→snapshot
p50 16.4ms. Cleared by measurement: extension ingress, relay forward/auth.

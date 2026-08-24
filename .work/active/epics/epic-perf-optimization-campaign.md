---
id: epic-perf-optimization-campaign
kind: epic
stage: drafting
tags: [perf]
parent: null
depends_on: []
release_binding: null
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

<!-- Children emitted by perf-design discovery; epic-design decomposition
follows if discovery reveals feature-scale arcs. -->

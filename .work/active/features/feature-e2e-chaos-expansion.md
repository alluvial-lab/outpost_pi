---
id: feature-e2e-chaos-expansion
kind: feature
stage: implementing
tags: [app, relay, pi-extension, testing]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# Chaos expansion: exhaust the reachable fault space around the live-oddities harness

Commissioned 2026-08-21 (operator: "build all of these"). Builds on the
completed `feature-e2e-live-oddities-suite` (device lane, 4 invariants,
3 toxic classes). Principle: chaos finds nothing; the ORACLE finds — so
invariants grow first, then fault vocabulary, then state diversity, then
structure (grid/mesh/cadence), then skew drills.

## Design decisions

- Device lane is single-serial (fixed emulator, fail-fast contention) →
  child verification is inherently sequential; workers scheduled in
  dependency+device order regardless of file disjointness.
- Known-open bugs (swallow, blank-chat) interacting with NEW scenarios:
  same xfail/skip-link discipline; soak expected-findings lists updated as
  discoveries surface. Discovered oddities get PARKED (capture + triage
  evidence), never hidden — the point of the program.
- Deterministic grid + property soaks complement randomized soaks.
- Fuzz stays N/A (no new parser surface).

## Children (implementation order)

1. `story-e2e-chaos-oracle-invariants` — no deps. New invariants: replay
   dedup (no duplicate delivery), transcript-DB ↔ rendered-UI consistency,
   canonical ordering, identity stability across faults.
2. `story-e2e-chaos-fault-vocabulary` — deps [1]. latency/bandwidth/slow_close
   toxics, relay kill (vs pause), compound faults, scheduler weights.
3. `story-e2e-chaos-state-shapes` — deps [1,2]. Multi-session switching,
   re-pair cycles, long-uptime/ring-rotation shapes.
4. `story-e2e-chaos-fault-moment-grid` — deps [2]. Deterministic fault×moment
   grid incl. pairing-handshake, hydration, QR-scan, mid-turn, cold-open.
5. `story-e2e-chaos-mesh-lane` — deps [2]. Second pi-host; mesh invariants
   (ingress queueing device-level, cross-Pi delivery).
6. `story-e2e-chaos-nightly-cadence` — deps [1,2]. VM-cron seeded soaks,
   report rotation, triage integration, expected-findings drift alerting.
7. `story-e2e-chaos-clock-version-skew` — deps [2]. libfaketime clock skew;
   version-skew relay drill (paired-wire-cut class). Exploratory-allowed.

## Risks

- Mesh lane may need pi-host adapter extensions (test-support scope).
- Skew drills may bounce (kernel/faketime constraints in containers) —
  allowed to land partial with findings parked.
- Nightly soaks on a fleet VM: schedule when idle; reports bounded.

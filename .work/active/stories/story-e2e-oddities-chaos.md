---
id: story-e2e-oddities-chaos
kind: story
stage: implementing
tags: [app, relay, pi-extension, testing]
parent: feature-e2e-live-oddities-suite
depends_on: [story-e2e-oddities-golden, story-e2e-oddities-failure, story-e2e-oddities-capture-triage]
release_binding: null
gate_origin: null
created: 2026-08-21
updated: 2026-08-21
---

# Chaos soak: randomized fault schedule against the four invariants

The transient-oddity reproducer. Randomized schedule over the fault
primitives with seeded RNG (reproducible), asserting the feature's four
invariants from the capture ring + transcript DB after the soak — using
`scripts/debug_capture_triage.py` as the oracle (anomalies → failures).
Test-integrity rules apply; soak failures get triaged via the tool, real
bugs parked, never hidden.

## Units

### Unit 1: `e2e/live_soak.py` (driver)
Seeded schedule (default 10 min, env-tunable): weighted picks over
{toxiproxy timeout/slicer/down, relay pause, pi-host /__restart, app
background, airplane} with hold times 2–60s; user-action cadence (sends,
navigation, cold restarts) interleaved. Post-run: pull captures + logs →
run triage tool → exit nonzero on invariant violations; report attributes
every connChannelLost with a cause (invariant 4 — also feeds
backlog-app-reconnect-churn attribution).

## Acceptance criteria
- [ ] One clean 10-minute soak on the VM (fleet idle): zero invariant
      violations, churn report generated.
- [ ] Seeded reproducibility: same seed → same schedule (unit-tested).
- [ ] Known-open-bug interactions surface as triage findings linked to
      their ids (e.g. swallow during identity window), not as silent
      passes.

---
id: feature-e2e-chaos-expansion
kind: feature
stage: done
tags: [app, relay, pi-extension, testing]
parent: null
depends_on: []
release_binding: v0.7.0
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


## Implementation summary (2026-08-22)

All 7 children done across 4 sequential workers (device lane forces serial).
One ENOSPC casualty mid-program (worker 2) — work recovered, verification
completed by the follow-up worker; disk hygiene now owned by the nightly
script (post-incident).

| story | commit | verification |
|---|---|---|
| oracle-invariants | 8020a33c | 4 invariants clean in seeded soak; 11 unit tests |
| fault-vocabulary | ca7e4a72 | latency/bandwidth/slow_close/relay_kill/compound demonstrated; determinism tests |
| state-shapes | 76a8f1e6 | multi-session/re-pair/long-uptime shapes in soak |
| fault-moment-grid | 3e89147e + 52cf059a | main 9/9 green; cold cells skip-linked green (post-correction run) |
| mesh-lane | 737787ab | 2nd pi-host; 3 mesh scenarios (1 linked skip) |
| nightly-cadence | c5a63889 | real 15-min manual run green; cron @02:30; bounded rotation; drift alerting |
| clock-version-skew | eeb68e12 | ±2h clock skew held invariants; v0.4.0 relay drill passed 16 current pairing tests |

**Program discoveries (the point of the exercise) — parked with evidence:**
1. `backlog-app-cold-replay-duplicates-persisted-transcript` — fresh process
   loses the replay seen-set; replays over persisted Hive rows (grid, caught
   live by the exact-one assertion).
2. `backlog-mesh-post-pair-roster-bootstrap-empty` (mesh lane).
3. Known-open set for the nightly drift check: the above + swallow +
   blank-chat (+ any the review confirms).

**Open question flagged for review:** v0.4.0 relay passing all 16 current
pairing tests vs AGENTS.md "hard cutover" claims for the paired wire —
either doc drift or a missing enforcement surface; adjudicate in review.


## Review record (2026-08-22)

**Standard weight, one independent pass** — fresh-context cross-model
reviewer (gpt-5.6-sol). Verdict: Request changes → **closed done** after
receiver-confirmed blocker fixes in 48863c19 (standard policy, no second
pass).

- **Blockers (4/4 confirmed, fixed + verified):** (1) nightly known-open
  inventory single-sourced + triage anomalies reconciled against fault
  windows (the exit-0-while-anomalies-FOUND failure mode eliminated);
  (2) DB↔UI oracle now claims and checks what it actually observes;
  (3) nightly multi-session marker replaced by real exerciseMultiSessionShape;
  (4) exclusive lane ownership — occupied serial fails fast without touching
  the foreign emulator (contention proof: second runner exit 2, first
  unharmed).
- **Important (2): folded** — nightly outer timeout + EXIT-trap hygiene +
  LAST_STATUS (silence ≠ health); skew-drill image pinning recorded.
- **Nit:** mesh-TTL claim narrowed to what the drill exercised.
- **Rejected (3):** hard-cutover question = drill-scope artifact (v0.4.0
  relay already post-cutover; enforcement tests exist at relay auth/pi_forward
  — no doc drift, no new bug); production-exposure and skip-link-scope
  concerns unsupported.
- Corrected count: the program parked THREE new oddities (state-shapes
  worker also found `backlog-app-session-rotation-late-echo-sticks-working`).
- Post-fix: 15 unit tests, real 300s soak exit 0 with 6-id inventory loaded
  and scheduled churn reconciled; 39G free.

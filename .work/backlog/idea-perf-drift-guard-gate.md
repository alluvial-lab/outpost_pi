---
id: idea-perf-drift-guard-gate
created: 2026-08-26
updated: 2026-08-26
tags: [workflow, performance, testing]
---

# Performance drift guard — metric without a gate

Operator observation (2026-08-26, mid-drain): performance is classed as a
product metric (reconnect hydration, delivery latency) but nothing guards
against drift. Every release gate checks correctness/hygiene (security,
tests, cruft, docs, patterns, refactor); none catches "still correct, now
slower."

## Why the gap is real right now

- **No bench infrastructure anywhere**: relay has no benches/ (no criterion
  in Cargo.toml), app/cockpit have no flutter benchmark deps, site has no
  perf budget tooling. There is nothing to drift *from* — no baselines
  exist.
- **This drain added timing-bearing surfaces**: durable outbox
  (persist-before-wire on every send), managed shutdown drain with cleanup
  deadline (replaced the fixed 100ms exit), reconnect hydration ordering.
  Their correctness is tested; their cost is not.
- **Known perf-shaped defects already parked**:
  `backlog-cockpit-terminal-output-backpressure`,
  `backlog-broker-audit-write-memory-ceiling`.

## Candidate surfaces to guard (product-ordered)

1. **App reconnect→hydration time** — the core mobile-remote UX metric
   (mobile-remote-coding's whole reason for being).
2. **Extension wake→delivery + agent_settled flush cost** — ingress batching
   exists; nothing pins its overhead.
3. **Send path latency incl. outbox persistence** (new this drain).
4. **Relay forwarding throughput/latency** (Rust; cheapest to bench).
5. **Cockpit terminal throughput** (already has a parked bug).

## Guard shapes, with the local honesty

This VM is load-sensitive (sync-service and audit-rotation flake history;
the PairingPage bisect methodology exists because of it). Wall-clock
pass/fail gates here would be flake factories. Ranked by viability:

1. **Deterministic count/algorithmic budgets in unit tests** — assert
   operation counts (e.g. hydration projects N events with O(N) merges, no
   O(N²) rescan), fake-clock timers. No wall clock at all. Fits the
   existing test tier; gate-tests already audits coverage value — a
   "perf-budget test" class needs no new gate to be enforced.
2. **Baseline-relative benches with tolerance** (criterion for relay,
   `flutter drive` benchmark harness for app) — trend detection, not hard
   gates; run on demand or dedicated quiet windows, never as CI pass/fail
   on the shared VM.
3. **E2E harness percentile capture** — extend run-pairing.sh to record
   timing percentiles per run into a tracked file; drift review at release
   time, human-adjudicated.

## Mechanism gap (important)

`gates_for_release` currently resolves to plugin skills; there is **no
`gate-perf` skill** in agile-workflow (adding `perf` to the list today would
halt release-deploy on skill resolution — same hazard class as the documented
`uat` non-slot). Real options:

- **Near-term, no new machinery**: perf budgets live in the test tier (shape
  1) and ride the existing tests gate; E2E percentile capture (shape 3) rides
  the release runbook.
- **Full gate**: new gate-perf skill in the skills repo (nklisch/agile-workflow
  plugin) — design-bearing upstream change, issue-first per the cross-repo
  rubric, then PR. Baseline storage + trend comparison + triage flow.

## Suggested route when picked up

Start with shape 1 budgets on surfaces 1-3 (highest product value, zero new
infra, zero flake risk) + shape 3 capture; treat the plugin gate-perf build
as a separate later decision once budgets exist to feed it. Possibly scope as
a feature via perf-design discovery mode.

---
id: gate-patterns-v0.7.0
kind: story
stage: implementing
tags: [patterns]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: patterns
created: 2026-08-24
updated: 2026-08-24
---

# Patterns extracted for v0.7.0

## New patterns codified

- `failure-first-regression-tests` — Start from the old failure boundary, assert the observable invariant, then verify repaired transitions.
- `golden-render-saving-comparators` — Capture through `matchesGoldenFile` with a saving comparator, then reject missing or blank evidence.
- `e2e-selector-harness-scenarios` — Map checked-in live-test selectors in the runner and let each harness scenario own setup, assertions, phases, and teardown.
- `generated-protocol-constant-consumption` — Consume generated protocol registries and limits at every language boundary instead of copying wire facts.
- `owner-channel-scoped-resource-ownership` — Bind retained resources to both owner identity and concrete channel, and tear down every matching index together.
- `asymmetric-threshold-stabilization` — Use separate entry/exit conditions or consecutive healthy probes to prevent noisy state flapping.
- `edge-triggered-convergence` — Notify, persist, or publish only when a validated semantic projection changes.

## Inconsistencies flagged

None.

## Pattern files written

- `.agents/skills/patterns/failure-first-regression-tests.md`
- `.agents/skills/patterns/golden-render-saving-comparators.md`
- `.agents/skills/patterns/e2e-selector-harness-scenarios.md`
- `.agents/skills/patterns/generated-protocol-constant-consumption.md`
- `.agents/skills/patterns/owner-channel-scoped-resource-ownership.md`
- `.agents/skills/patterns/asymmetric-threshold-stabilization.md`
- `.agents/skills/patterns/edge-triggered-convergence.md`
- `.agents/skills/patterns/SKILL.md` (updated index)
- `.agents/rules/patterns.md` (generated hook-loaded digest)

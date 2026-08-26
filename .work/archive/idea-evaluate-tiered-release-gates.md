---
id: idea-evaluate-tiered-release-gates
created: 2026-08-11
updated: 2026-08-26
tags: [workflow]
status: superseded
superseded_by: all-gates posture ratified (operator, E4A) — decision recorded in .work/CONVENTIONS.md gates_for_release; groom 2026-08-26
---

# Evaluate formalizing the tiered release-gate model

## Resolved (2026-08-26, operator E4A)

Post-trial releases (v0.5.0 post-hoc, v0.7.0, v0.8.0) all ran the full
gate suite — the trial lapsed by default rather than by decision (the word
"tiered" appears nowhere after the v0.4.0 record). Operator ratified the
all-gates posture on 2026-08-26: proportionality is handled by two-lane
release slicing (fix/feature lanes), not gate tiering. Decision recorded in
`.work/CONVENTIONS.md` → `gates_for_release`.

## Context

For `release-v0.4.0` we trial-ran a **2-dimensional gate split** instead of the
default "all configured gates over the whole release bundle":

- **Feature work** (non-`gate_origin` items) → run **all 6 gates**
  (security, tests, refactor, cruft, docs, patterns). New code deserves full
  hygiene + bug-catch coverage.
- **Gate-origin work** (`gate_origin` items — prior gate outputs) → run
  **security only** (regression-confirm). Re-running cruft/docs/patterns on items
  that *are* such findings is circular; security earns a re-run because a later
  commit breaking prior hardening is high-stakes and cheap to confirm.

The current `CONVENTIONS.md` says run all configured gates for every release
(`release-deploy` Phase 4 guardrail: "Don't bypass gates"). The tiered model
bends that with an operator judgment for v0.4.0.

## Evaluate after v0.4.0 ships

- Did the scoped scans catch real issues in the feature work? (value)
- Did skipping hygiene gates on gate-origin work miss anything? (risk)
- Was the cost proportionate vs. the all-6×60 default? (efficiency)
- Did the security regression sweep on the 14 security-origin items find any
  regressions, or was it circular too? (whether even security merits re-run)

If it held up, formalize in `CONVENTIONS.md` as the default posture — e.g. a
`tiered_gates` rule: full gates on non-`gate_origin` code; security-only
regression on `gate_origin` code. If it didn't, revert to all-gates and note
why. Either way, record the decision so this isn't relitigated each release.

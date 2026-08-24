---
id: release-v0.7.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Release v0.7.0

First gated release since v0.4.0 (v0.5.0 was tagged out-of-flow, bound
retroactively, gates post-hoc). This release claims everything since:
48 active done items + 7 late-bound archived stubs, spanning the upstream
harvest, the live-oddities + chaos e2e program (incl. nightly cadence and
skew drills), six mobile fix families (swallow/blank/dedup/working/churn/
reconnect UX), the fold/split-screen usability pass, debug-capture
delivery (schema+extension+app), the four routed v0.5.0 post-hoc gate
findings, and the CI emulator job.

## Bound items

- 48 active done items (see work-view --release v0.7.0): features
  upstream-harvest, e2e-live-oddities-suite, e2e-chaos-expansion,
  fold-usability-pass, debug-capture-delivery + all child stories +
  standalone fix stories + gate-* carryovers + story-ci-android-emulator-test-job.
- 7 late-bound archived stubs (unbound at gather; archived_atop retained
  as provenance).

### Binding-consistency warnings (guard: warn, cohesion: phased)

- CONFLICT ×4 resolved at bind: archived parent stubs
  epic-targeting-and-session-lifecycle-contracts and
  feature-reconnect-reproduction were unstamped v0.1.0-era leaks (children
  bound v0.1.0); stamped to v0.1.0 and removed from this bundle.
- INCOMPLETE ×3 fixed: three chaos-expansion stories missed by the
  work-view gather (index lag); bound directly.

## Gate runs

- **gate-tests** (2026-08-24) — 6 findings (High=5, Low=1; 5 coverage gaps, 1 low-value-test removal)

(planned: security, tests, cruft, docs, patterns, refactor — then manual UAT)

- **gate-security** (2026-08-24) — 2 findings (High=1, Medium=1; inline scanner, reduced isolation)

---
id: feature-ci-verification-matrix
kind: feature
stage: drafting
tags: [workflow, security]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-07-23
---

# CI verification matrix + dependency-audit automation

## Brief

The only workflow running on push/PR today is `e2e-pairing.yml`. There is no
routine lint/typecheck/test matrix across the five subprojects and no
dependency-audit automation — both the repo-eval and the 2026-07 advisor
review flagged this as the weakest dimension (CI/CD 4/10). The 0.2.0 release
history shows the cost: test regressions and doc drift surfaced during the
release gates instead of per-push.

Add a push/PR verification matrix covering the documented per-subproject
checks (AGENTS.md "Common commands"):

- `pi-extension/`: `corepack pnpm typecheck`, `corepack pnpm test`
- `app/`: `flutter analyze`, `flutter test`
- `relay/`: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test`
- `cockpit/`: `flutter analyze`, `flutter test`
- `site/`: `pnpm lint`, `pnpm build`

Plus dependency-audit automation: Dependabot (or Renovate) config covering
pnpm/cargo/pub ecosystems, and an audit job (`pnpm audit`, `cargo audit` or
`cargo-deny`) with a documented severity threshold. Dependabot alerts already
fire on the repo (see commit `a049b09`) but nothing gates on them.

## Simplification opportunity

Path-filtered job triggering (only run a subproject's lane when its files
change) keeps the matrix cheap; a shared composite action for Flutter setup
avoids duplicating toolchain pinning across app/cockpit lanes. The existing
`e2e-pairing.yml` setup steps (Flutter install, pnpm setup) are the starting
point to factor out.

## Origin

Advisor review 2026-07-23, recommendation #1. Broadens parked backlog item
`workflow-ci-dependency-audit-gates` (repo-eval + security review finding).

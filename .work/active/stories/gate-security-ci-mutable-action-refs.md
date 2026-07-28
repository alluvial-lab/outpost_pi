---
id: gate-security-ci-mutable-action-refs
kind: story
stage: review
tags: [security, workflow]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-24
updated: 2026-07-28
---

# CI executes mutable action references

## Source
gate-security scan for v0.3.0 (2026-07-24). Severity: Medium → parked per gate_finding_routing.

## Domain
Infrastructure & Deployment / Supply Chain

## Location
`.github/workflows/ci.yml:25`; `.github/workflows/deps-audit.yml:38`; `.github/workflows/e2e-pairing.yml:24`

## Evidence
Workflows execute major-version or mutable refs (actions/checkout@v4, dorny/paths-filter@v3, subosito/flutter-action@v2, dtolnay/rust-toolchain@stable, taiki-e/install-action@cargo-audit) rather than immutable commit SHAs. Retargeting or compromise of an upstream action ref gives its publisher code execution in CI — test-result manipulation or cache poisoning. Restricted workflow permissions reduce repo-write impact but do not preserve verification integrity.

## Remediation direction
Pin every action to a reviewed full commit SHA and let the existing GitHub Actions Dependabot entry propose controlled SHA updates.

## Implementation notes
- Pinned every `uses:` reference in the owned `.github/workflows/ci.yml` workflow to a full commit SHA with its reviewed tag/branch retained as an inline comment.
- Verification: checked that `ci.yml` has no `uses:` reference at `@v…` or `@stable`; the prior relay `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` run remained green.
- Parked issues: the finding also names `deps-audit.yml` and `e2e-pairing.yml`, but this story's assigned write scope is `ci.yml` only; their refs require separately scoped follow-up.

---
id: gate-security-ci-mutable-action-refs
created: 2026-07-24
updated: 2026-07-24
tags: [security]
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

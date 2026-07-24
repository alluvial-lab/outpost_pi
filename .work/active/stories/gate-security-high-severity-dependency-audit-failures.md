---
id: gate-security-high-severity-dependency-audit-failures
kind: story
stage: implementing
tags: [security]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: security
created: 2026-07-24
updated: 2026-07-24
---

# Checked-in dependencies currently fail the high-severity audit

## Severity
High

## Domain
Dependencies & Supply Chain

## Location
`site/pnpm-lock.yaml:1568,1767`; `pi-extension/pnpm-lock.yaml:848,1007`

## Evidence
Read-only `pnpm audit` exits nonzero with high advisories: site locks next@16.2.10 and sharp@0.34.5; extension locks brace-expansion@5.0.6 and fast-uri@3.1.2. Advisories include Next.js SSRF/DoS/bypass, libvips via Sharp, brace-expansion exponential-time DoS, fast-uri host-confusion. The new deps-audit workflow is already red under its stated high+ threshold.

## Remediation direction
Update Next.js to >=16.2.11, Sharp to >=0.35.0, fast-uri to >=3.1.4, brace-expansion to >=5.0.7, directly or through parent dependency updates. Require clean audit results before release.

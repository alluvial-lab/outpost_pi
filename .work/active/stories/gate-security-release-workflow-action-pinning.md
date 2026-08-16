---
id: gate-security-release-workflow-action-pinning
kind: story
stage: review
tags: [workflow, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-08-15
updated: 2026-08-16
---

# Pin mutable GitHub Actions refs in the release workflows (signing/publishing authority)

Post-hoc v0.5.0 security-gate finding. Severity: **High** — supply chain.

## Severity
High

## Domain
Dependencies & Supply Chain

## Location
- `.github/workflows/app-release.yml:41,56,60` — 3 mutable refs (`actions/checkout@v7`, `actions/setup-java@v5`, `subosito/flutter-action@v2`); job holds `GH_TOKEN` + release/signing authority
- `.github/workflows/cockpit-release.yml` — **12 mutable refs**, same release authority class

## Evidence
```yaml
env:
  GH_TOKEN: ${{ github.token }}
steps:
  - uses: actions/checkout@v7   # mutable tag
```
v0.4.0's `gate-security-ci-mutable-action-refs` pinned `ci.yml` only (18
refs, all SHA-pinned today). `backlog-ci-pin-deps-audit-e2e-pairing-refs`
tracks `deps-audit.yml` + `e2e-pairing.yml`. The **release** workflows —
the ones holding write tokens and signing/publishing secrets — were never
swept and are the worst offenders.

## Remediation direction
Pin every third-party action ref in both release workflows to a reviewed
commit SHA with the digest noted in a comment, matching the `ci.yml`
treatment; configure dependabot to keep the SHA pins current. Sibling:
`backlog-ci-pin-deps-audit-e2e-pairing-refs` (complete together if cheap).

## Implementation

Pinned all mutable action refs to the SHA resolved from their current tag,
with the resolved release noted in trailing comments:

- `.github/workflows/app-release.yml`: 3 refs pinned (checkout, setup-java,
  flutter-action).
- `.github/workflows/cockpit-release.yml`: 12 refs pinned (checkout,
  flutter-action, upload-artifact, and download-artifact).
- `.github/workflows/deps-audit.yml`: 5 action occurrences pinned across 4
  distinct refs (checkout appears in both jobs; also pnpm/action-setup,
  setup-node, and taiki-e/install-action).
- `.github/workflows/e2e-pairing.yml`: 4 refs pinned (checkout,
  pnpm/action-setup, setup-node, and flutter-action).

The existing `.github/dependabot.yml` `github-actions` entry at `/` already
runs weekly and covers every workflow under `.github/workflows/`; no config
change was required. The sibling backlog item is absorbed by this work and
will be archived by the orchestrator.

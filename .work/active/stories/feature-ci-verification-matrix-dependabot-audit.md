---
id: feature-ci-verification-matrix-dependabot-audit
kind: story
stage: implementing
tags: [workflow, security]
parent: feature-ci-verification-matrix
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-23
updated: 2026-07-23
---

# Dependabot config + audit coverage

## Brief

Design Unit 2 of the parent feature. New `.github/dependabot.yml` covering
github-actions (root), npm (/pi-extension, /site, /protocol, /e2e,
/tools/protocol-codegen), cargo (/relay, /rp-s3), pub (/app, /cockpit,
/app/packages/outpost_pi_identity) — weekly, open-pull-requests-limit 5,
commit prefixes matching the `deps(site): …` precedent. Verify whether the
protocol pnpm workspace needs one entry or per-package entries. Fallback if
pub ecosystem errors: drop pub entries, rely on `dart pub outdated` in the
weekly audit job.

Acceptance: config validates on merge (no Dependency-graph config errors);
audit job fails on a deliberately introduced high-severity advisory
(throwaway branch, then reverted).

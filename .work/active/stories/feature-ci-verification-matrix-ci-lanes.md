---
id: feature-ci-verification-matrix-ci-lanes
kind: story
stage: done
tags: [workflow]
parent: feature-ci-verification-matrix
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-23
updated: 2026-07-23
---

# CI verification lanes (ci.yml)

## Brief

Design Unit 1 of the parent feature. New `.github/workflows/ci.yml` with a
`dorny/paths-filter` change-detection job gating six lanes: protocol
(check scripts), pi-extension (typecheck + test), rust matrix [relay, rp-s3]
(fmt + clippy -D warnings + test), app (analyze + test + nested
outpost_pi_identity package), cockpit (analyze + test), site (lint + build),
plus the `deps-audit` job (weekly cron + lockfile-path pushes, high/critical
threshold). Setup patterns copy `e2e-pairing.yml` (pnpm 10, node 24,
Flutter 3.41.7 via env). No artifact packaging — release workflows own that.

Acceptance: all lanes green on a full-tree push; docs-only push runs zero
lanes; protocol-only push runs protocol + pi-extension + app lanes;
e2e-pairing.yml unaffected.

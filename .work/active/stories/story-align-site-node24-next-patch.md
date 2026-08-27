---
id: story-align-site-node24-next-patch
kind: story
stage: implementing
tags: [site, deps]
parent: feature-stack-currency-review
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Site: Node 24 CI/Docker/engine alignment + Next 16.3.3 patch

Align CI node-version, Dockerfile base, and package engine field on one Node (24); Next patch bump; pnpm check green.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

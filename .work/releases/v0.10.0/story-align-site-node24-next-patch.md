---
id: story-align-site-node24-next-patch
kind: story
stage: done
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

## Closure

- Site CI already used Node 24 (`.github/workflows/ci.yml`); it remains aligned.
- All Docker stages now use `node:24-alpine` instead of `node:22-alpine`.
- Added `engines.node: ">=24.0.0"`; no Volta field was present.
- Bumped `next` and matching `eslint-config-next` from 16.3.0 to 16.3.3 and refreshed `site/pnpm-lock.yaml` (patch only).
- Verification: `pnpm install` completed with the refreshed lockfile; `pnpm check` passed lint, build, and all 19 browser tests (the current suite has 19, not 18). `docker build --tag outpost-pi-site:node24-check site` passed on Node 24 Docker stages.

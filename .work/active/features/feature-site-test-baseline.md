---
id: feature-site-test-baseline
kind: feature
stage: drafting
tags: [site, testing]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Site test baseline (with light/dark contract as first coverage)

## Brief

Formed by groom 2026-08-26: `idea-site-test-baseline` (site/ has zero test
files) and `gate-tests-site-light-dark-contract` (no reproducible
light/dark/contrast check) are one test program — the light/dark contract is
the concrete first story under the broader baseline, not a separate program.

Sources (bodies retained in `.work/archive/`).

## Work

1. **Thin baseline** — a smoke render test per route or a link/metadata
   check, wired into the `pnpm lint`/`pnpm build` workflow (`site/` commands
   per AGENTS.md).
2. **Light/dark computed-style contract** — browser/computed-style test over
   four partitions: system-dark (no attr), system-light (no attr),
   forced-dark under light system, forced-light under dark system. Assert
   resolved key roles + AA ratios from `globals.css` (`:86` explicit light
   values, `:114` system-light overrides), not screenshots. Replaces the
   one-time contrast/alias scans recorded in `story-brand-site-sync`.

Out of scope (noted, opportunistic): `globals.css` is 2282 LOC and may
warrant a split at the next styling pass.

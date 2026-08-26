---
id: gate-docs-site-readme-playwright-workflow
created: 2026-08-26
updated: 2026-08-26
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Site command guidance omits the checked-in Playwright and check workflow

## Drift category
readme-staleness

## Location
- Doc: `site/README.md:34-42`; `AGENTS.md:74-76`
- Contradicting source: `site/package.json:9-12`; `.github/workflows/ci.yml:254-258`

## Current doc text
> The site README lists `pnpm install`, `pnpm dev`, `pnpm build`, and `pnpm lint`, while the root common commands list `pnpm lint && pnpm build`.

## Contradiction
The site now has a checked-in `pnpm test` Playwright suite and an ordered `pnpm check` command, and CI installs Chromium before running that check. The operator-facing command references still describe the older lint/build-only verification and do not expose the new production browser baseline.

## Required edit
Add `pnpm test` and the canonical `pnpm check` command to the site README and root common commands. Mention the Chromium prerequisite or link to the site test workflow so local verification matches CI.

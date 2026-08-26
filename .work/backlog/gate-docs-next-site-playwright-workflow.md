---
id: gate-docs-next-site-playwright-workflow
created: 2026-08-26
updated: 2026-08-26
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Next-site skill omits the new Playwright verification contract

## Drift category
repo-skill-staleness

## Location
- Doc: `.agents/skills/next-site/SKILL.md:20-35`
- Contradicting source: `site/package.json:9-12`; `site/playwright.config.ts:1-30`; `.github/workflows/ci.yml:254-258`

## Current doc text
> The Commands section lists `pnpm install`, `pnpm dev`, `pnpm lint`, `pnpm build`, and `pnpm start`; the deploy command remains `pnpm lint && pnpm build`.

## Contradiction
The site now owns a Chromium-backed route/theme baseline, an ordered `pnpm check` script, and a CI Chromium installation step. The stack reference does not tell agents to run or satisfy that baseline, leaving its verification instructions behind the current package and workflow contract.

## Required edit
Add `pnpm test`/`pnpm check` and the single-Chromium prerequisite to the command and verification guidance. Use `pnpm check` in the deploy verification wording while retaining lint/build as independently available commands.

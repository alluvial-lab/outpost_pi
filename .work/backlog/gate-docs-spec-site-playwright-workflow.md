---
id: gate-docs-spec-site-playwright-workflow
created: 2026-08-26
updated: 2026-08-26
tags: [documentation]
release_binding: null
gate_origin: docs
---

# SPEC verification commands omit the new site browser baseline

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/SPEC.md:143-145`
- Contradicting source: `site/package.json:9-12`; `.github/workflows/ci.yml:254-258`

## Current doc text
> `# site/` followed by `pnpm lint && pnpm build`

## Contradiction
The v0.9.0 site contract now includes Playwright route/theme tests and the ordered `pnpm check` script. The authoritative verification section still presents lint/build as the complete site check, so following the foundation command omits the browser baseline that CI runs.

## Required edit
Use `pnpm check` for the site verification command and note that local/CI setup must provide the single Chromium project before the production `next start` browser tests run.

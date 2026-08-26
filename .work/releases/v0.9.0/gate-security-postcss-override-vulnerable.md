---
id: gate-security-postcss-override-vulnerable
kind: story
stage: done
tags: [site, pi-extension, security]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: security
created: 2026-08-15
updated: 2026-08-26
---

# pnpm overrides pin PostCSS to a version vulnerable to source-map file reads

Post-hoc v0.5.0 security-gate finding. Severity: Medium (Ambient — dev-time
exposure via malicious CSS/source maps).

## Location
`site/pnpm-workspace.yaml:14` (and the same override shape in `pi-extension`):
`postcss: 8.5.18` forced below the fix; `pnpm audit` flags GHSA-fxqj-rqcc-2cmp
(arbitrary source-map file read) in both dependency graphs.

## Work
Remove or advance the override to PostCSS ≥ 8.5.23 after compatibility
verification against the Tailwind/Next toolchain.

## Implementation notes
- Execution capability: Inline host implementation; the caller selected `openai-codex/gpt-5.6-luna` xhigh for this worker. The focused two-subproject dependency and lockfile update required no fan-out.
- Review weight: standard (caller/autopilot note).
- Files changed: `site/pnpm-workspace.yaml`, `site/pnpm-lock.yaml`, `pi-extension/pnpm-workspace.yaml`, `pi-extension/pnpm-lock.yaml`.
- Tests added/removed: none; existing site browser coverage and Pi extension suites exercised the updated dependency graphs.
- Simplification: none; advanced the existing PostCSS security override from `8.5.18` to the patched `8.5.23` rather than removing the override needed to keep the dependency graphs aligned.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Bounded inline review: no material blockers; both `site/package.json` and `pi-extension/package.json` were checked and contain no direct PostCSS pin or override, while the workspace overrides and lockfiles consistently resolve `8.5.23`.
- Audit delta: baseline `pnpm audit --audit-level=low` reported one moderate PostCSS advisory in each graph; after lockfile regeneration and install, both audits report `No known vulnerabilities found`.
- Verification: site `pnpm check` passed (lint, production build, and 18 Playwright tests; using the preinstalled browser cache); pi-extension `corepack pnpm typecheck`, `corepack pnpm test` (60 files, 1102 passed, 3 skipped), and `corepack pnpm build` passed.

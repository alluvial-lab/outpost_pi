---
id: gate-security-postcss-override-vulnerable
created: 2026-08-15
updated: 2026-08-15
tags: [site, pi-extension, security]
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

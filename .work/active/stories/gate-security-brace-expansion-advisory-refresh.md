---
id: gate-security-brace-expansion-advisory-refresh
kind: story
stage: implementing
tags: [security]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: security
created: 2026-07-24
updated: 2026-07-24
---

# brace-expansion pin is now itself inside a new advisory range

## Severity
High

## Domain
Dependencies & Supply Chain

## Location
`pi-extension/pnpm-workspace.yaml:11`; `site/pnpm-workspace.yaml:8-9`

## Evidence
Orchestrator-verified 2026-07-24: GHSA-mh99-v99m-4gvg (DoS via unbounded
expansion length → OOM) covers `<=5.0.7`, patched `>=5.0.8`. The drain
pinned 5.0.7 against the older advisory. `pnpm audit --prod` in
pi-extension reports one high (Pi SDK → glob/minimatch → 5.0.7); site
reports the same high in dev tooling (eslint → config-array → minimatch).
`.github/workflows/deps-audit.yml` is red at the high threshold.

## Remediation direction
Move both workspace overrides to `brace-expansion@5: 5.0.8` (keep the `@1`
pin at 1.1.16 unless it is also in range — verify), regenerate both
lockfiles, verify compatibility with older minimatch consumers, and rerun
the exact CI audit commands (prod for extension, full for site) clean.

## Acceptance
- `pnpm audit --prod --audit-level=high` clean in pi-extension;
  `pnpm audit --audit-level=high` clean in site.
- Frozen installs, extension typecheck/build, site lint/build green.

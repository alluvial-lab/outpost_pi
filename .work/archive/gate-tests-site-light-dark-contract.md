---
id: gate-tests-site-light-dark-contract
created: 2026-08-15
updated: 2026-08-26
tags: [site, testing]
status: folded
folded_into: feature-site-test-baseline (groom 2026-08-26)
---

# Site light/dark resolution and AA contrast have no reproducible automated check

Post-hoc v0.5.0 tests-gate finding. Severity: Medium.

## Location
`site/src/app/globals.css:86` (explicit light values) and `:114` (system-light
overrides duplicated separately). No test/spec files exist in `site/`; the
one-time contrast/alias scans recorded in `story-brand-site-sync` are not
reproducible.

## Work
Lightweight browser/computed-style contract test over four partitions:
system-dark (no attr), system-light (no attr), forced-dark under light system,
forced-light under dark system. Assert resolved key roles + AA ratios, not
screenshots.

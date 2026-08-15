---
id: gate-tests-theme-dual-mode-contrast
created: 2026-08-15
updated: 2026-08-15
tags: [app, cockpit, testing]
---

# Theme tests assert literals but not effective dual-mode wiring or AA contrast

Post-hoc v0.5.0 tests-gate finding. Severity: Medium.

## Location
`app/test/ui/core/themes/app_theme_test.dart:8,22,36` and
`cockpit/test/core/ui/themes/app_theme_test.dart:9,22,35` assert registry
literals + font names only; public builders at
`app/lib/ui/core/themes/app_theme.dart:74-84` /
`cockpit/lib/app/core/ui/themes/app_theme.dart:19-45` are never invoked.

## Work
Property-oriented tests for both builders: correct brightness, token
extensions, semantic ColorScheme wiring, and WCAG ratios for
primary-text/bg, muted-text/bg, accent/bg, on-accent/accent. Keep literal
identity assertions only for the locked brand contract. Natural home for the
shared cross-surface fixture noted in the
`paired-brightness-semantic-palettes` pattern's drift risks.

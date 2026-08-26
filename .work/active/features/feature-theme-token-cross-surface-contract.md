---
id: feature-theme-token-cross-surface-contract
kind: feature
stage: drafting
tags: [app, cockpit, branding, testing]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Theme token cross-surface contract (generate/golden the ports + dual-mode contrast tests)

## Brief

Formed by groom 2026-08-26 from two items that are the two halves of one
contract problem: `gate-patterns-v050-token-port-drift` is the drift risk,
`gate-tests-theme-dual-mode-contrast` is explicitly its verification half
("natural home for the shared cross-surface fixture noted in the
`paired-brightness-semantic-palettes` pattern's drift risks").

Sources (bodies retained in `.work/archive/`).

## Work

1. **Token-port drift** — `tokens.css` is ported by hand into app and cockpit
   Dart with duplicated literal assertions and no shared cross-surface
   fixture; any contract change risks silent per-surface drift. Direction:
   generate or golden-test the ports against the contract
   (`.mockups/design-system/tokens.css` is the contract per AGENTS.md).
2. **Dual-mode theme property tests** — current theme tests assert registry
   literals + font names only; public builders
   (`app/lib/ui/core/themes/app_theme.dart:74-84`,
   `cockpit/lib/app/core/ui/themes/app_theme.dart:19-45`) are never invoked.
   Property-oriented tests for both builders: correct brightness, token
   extensions, semantic ColorScheme wiring, WCAG AA ratios for
   primary-text/bg, muted-text/bg, accent/bg, on-accent/accent. Keep literal
   identity assertions only for the locked brand contract.
3. **Mark geometry triple-encoding** (carried from the token-port item) —
   Constellation III encoded in Python (`scripts/generate-brand-assets.py:19-56`),
   canonical SVG (`branding/`, declared source of truth), and independently
   in `site/src/app/opengraph-image.tsx:37-46`. Single-source the geometry.

The shared cross-surface fixture from (2) is the anchor (1) generates or
golds against — design them together.

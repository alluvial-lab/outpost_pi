---
id: gate-docs-pattern-palette-anchor
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: docs
created: 2026-08-24
updated: 2026-08-24
---

# Paired-palette pattern anchors no longer show theme resolution

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/paired-brightness-semantic-palettes.md:38-42`
- Contradicting source: `app/lib/ui/core/themes/app_theme.dart:103-119`

## Current doc text
> Flutter resolves the pair at the theme builder — `app_theme.dart:74-84`.

## Contradiction
The cited range is now input-decoration styling, not brightness resolution. The
current theme builder's `buildDarkTheme`/`buildLightTheme` pair and token wiring
are at lines 97-107, so the pattern example sends readers to unrelated code
after the release UI changes.

## Required edit
Refresh the Flutter theme-builder anchor and snippet to the current dark/light
resolution and semantic-token wiring.

## Implementation

Corrected `.agents/skills/patterns/paired-brightness-semantic-palettes.md` to
anchor the Flutter dark/light builders and semantic token wiring at
`app/lib/ui/core/themes/app_theme.dart:97-107`. The finding was valid and
corrected; no rejection was necessary.

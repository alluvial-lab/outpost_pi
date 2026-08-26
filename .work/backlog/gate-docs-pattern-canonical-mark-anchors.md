---
id: gate-docs-pattern-canonical-mark-anchors
created: 2026-08-26
updated: 2026-08-26
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Canonical-mark pattern points at stale generator line ranges

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/canonical-mark-rasterization-fanout.md:31-34`
- Contradicting source: `scripts/generate-brand-assets.py:19-74,99-199,212-247`

## Current doc text
> `draw_mark` is cited at `19-56`, Android densities at `79-96`, iOS/macOS at `98-115`, Windows at `117-121`, and later platform ranges.

## Contradiction
The generator gained the canonical `MarkGeometry` input and shifted the fan-out ranges. Lines `79-96` now contain `save_existing_mark`, while Android starts at `99` and the iOS/macOS, Windows, and remaining platform blocks occur later. Agents following the pattern are sent to unrelated code and may miss the canonical geometry boundary.

## Required edit
Refresh every file:line anchor to the current `draw_mark`, Android, iOS/macOS, Windows, cockpit/web, site favicon, and banner blocks. Preserve the current contract-maintenance claim that geometry comes from `branding/logo-foreground.svg` and the TypeScript projection is generated.

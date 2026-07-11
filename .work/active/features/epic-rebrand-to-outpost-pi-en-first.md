---
id: epic-rebrand-to-outpost-pi-en-first
kind: feature
stage: drafting
tags: [rebrand, cockpit, app, docs, i18n]
parent: epic-rebrand-to-outpost-pi
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-11
updated: 2026-07-11
---

# EN-first pass: replace Portuguese with English in shipped product

## Brief

A separable workstream from the rename itself: replace Portuguese (PT) with
English (EN) in all shipped product code, docs, comments, and UI strings.
The bulk is in `cockpit/` (~186 files with accented Latin / PT comments and
strings); `app/` has a smaller PT footprint.

Per the locked strategic decision and the operator boundary confirmed in the
epic: **leave `scripts/` operator-glue shell comments untouched** — those are
operator-facing automation glue, not shipped product, and rewriting is churn
without product value.

This is parallel-able with the rename and provenance features; it does not
touch wire-stable identifiers or product identity strings.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi`
- Position in epic: **parallel workstream.** Distinct concern from the
  rename (class 1), wire migration (class 2), and provenance (class 3). Can
  proceed independently or as a follow-up. No dependency on any sibling
  feature.

## What this feature does NOT cover
- `scripts/` shell comments — explicitly out of scope (operator glue).
- PT in generated/vendored files (`.pub-cache/`, `node_modules/`,
  `.xdg-cache/`) — out of scope, not shipped product.
- Any product-identity string rename (that's the mechanical-rename feature).
- Wire-stable identifiers (that's the wire-and-install-stable-migration
  feature).

## Foundation references
- Parent epic `## EN-first scope` — the boundary decision and `scripts/`
  exclusion.

## Design notes (for `/agile-workflow:feature-design`)

- This is a large, mechanical translation pass — the design pass should
  consider whether to split by subproject (cockpit-first, since it holds the
  bulk) and whether any PT strings are user-visible UI text requiring
  translation-review rather than a mechanical rewrite.
- Confirm with the operator whether any PT terms are intentional
  domain vocabulary to preserve before bulk-translating.
- Cockpit's `flutter analyze` and `flutter test` (per `.agents/rules/`)
  gate the slice; the EN pass must not break either.

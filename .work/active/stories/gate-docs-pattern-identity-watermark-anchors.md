---
id: gate-docs-pattern-identity-watermark-anchors
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: docs
created: 2026-08-24
updated: 2026-08-24
---

# Identity-watermark pattern anchors point at unrelated storage code

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/identity-scoped-monotonic-high-watermarks.md:10-67`
- Contradicting source: `app/lib/pairing/storage.dart:515-583` and `pi-extension/src/pairing/storage.ts:589-629`

## Current doc text
> App channel counters merge only under matching directional keys — `app/lib/pairing/storage.dart:480-507`.
> Extension send reservations ... `pi-extension/src/pairing/storage.ts:419-430`.
> Extension receive acceptance ... `pi-extension/src/pairing/storage.ts:443-460`.

## Contradiction
Those cited ranges now show peer reads/key declarations rather than the quoted
monotonic channel reservations. The current app merge is around 515-583; the
extension send/receive high-water operations are around 589-629.

## Required edit
Refresh all three channel-counter anchors and snippets to the current serialized,
identity-checked implementations, preserving the pattern's monotonicity claim.

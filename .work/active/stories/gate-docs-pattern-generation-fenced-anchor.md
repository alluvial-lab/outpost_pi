---
id: gate-docs-pattern-generation-fenced-anchor
kind: story
stage: review
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: docs
created: 2026-07-24
updated: 2026-07-24
---

# Generation-fenced ownership pattern points to the pre-watermark mesh implementation

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/generation-fenced-async-ownership.md:88-102`
- Contradicting source: `app/lib/data/mesh/mesh_sync_service.dart:300-344`

## Current doc text
> Example anchors app/lib/data/mesh/mesh_sync_service.dart:200-224.

## Contradiction
That range now covers fetch-result handling. The quoted cache-replacement fence moved under _replaceLocalCacheWith after the owner-bound durable watermark serialization was added.

## Required edit
Update the anchor and example to the current owner-bound _replaceLocalCacheWith implementation.

## Implementation notes

Updated the pattern anchor and cache-replacement example to match the current owner-bound implementation at `mesh_sync_service.dart:300-344`.

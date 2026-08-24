---
id: gate-docs-pattern-generation-fenced-anchors
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

# Generation-fenced pattern anchors no longer quote the current implementations

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/generation-fenced-async-ownership.md:54-91`
- Contradicting source: `app/lib/data/sync/sync_service.dart:334-379` and `app/lib/data/mesh/mesh_sync_service.dart:324-344`

## Current doc text
> Sync activation fences each durable hydration phase — `app/lib/data/sync/sync_service.dart:257-293`.
> Mesh pull validates its mutation revision throughout cache replacement — `app/lib/data/mesh/mesh_sync_service.dart:300-344`.

## Contradiction
The cited sync range now contains compatibility getters, while the generation
activation and hydration sequence is at lines 338-385. The mesh range begins in a
comment block; `_replaceLocalCacheWith` begins at line 324 and its current body no
longer matches the quoted range's claimed anchor.

## Required edit
Refresh the pattern's file:line anchors and quoted snippets against the current
sync activation and mesh cache-replacement implementations.

## Implementation

Corrected `.agents/skills/patterns/generation-fenced-async-ownership.md` to cite
`_activateForGeneration` at `app/lib/data/sync/sync_service.dart:338-385` and
`_replaceLocalCacheWith` at `app/lib/data/mesh/mesh_sync_service.dart:324-407`,
with current generation checks and cache mutation guards. The finding was valid
and corrected; no rejection was necessary.

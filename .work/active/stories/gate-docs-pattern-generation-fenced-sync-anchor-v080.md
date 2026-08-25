---
id: gate-docs-pattern-generation-fenced-sync-anchor-v080
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: docs
created: 2026-08-25
updated: 2026-08-25
---

# Generation-fenced pattern points at the pre-reducer sync activation range

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/generation-fenced-async-ownership.md:72-90`
- Contradicting source: `app/lib/data/sync/sync_service.dart:363-410`

## Current doc text
> Sync activation fences each durable hydration phase — `app/lib/data/sync/sync_service.dart:338-385`.

## Contradiction
The incremental transcript reducer and hydration-window changes shifted `_activateForGeneration` to line 363 and its guarded `_loadIndex`/projection/pending-send sequence to lines 397-410. The cited range begins in the preceding activation path and does not identify the complete fenced sequence described by the pattern.

## Required edit
Refresh the sync activation anchor and snippet to the current `_activateForGeneration` and its post-await lifecycle checks. Keep the chat and mesh examples unchanged only if their cited ranges still match.

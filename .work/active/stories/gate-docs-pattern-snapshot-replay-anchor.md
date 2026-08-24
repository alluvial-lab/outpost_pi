---
id: gate-docs-pattern-snapshot-replay-anchor
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

# Snapshot-replay pattern points at a non-mapper extension line

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/snapshot-replay-event-mappers.md:40-90`
- Contradicting source: `pi-extension/src/session/transcript_projection.ts:144-150`

## Current doc text
> Extension compatibility + legacy snapshot adapter — `pi-extension/src/session/transcript_projection.ts:131`.

## Contradiction
Line 131 is now the end of a compaction-event switch. The documented
`mapLegacyAgentMessagesToTranscriptEvents` adapter begins at line 144, so the
pattern's named example does not resolve to the implementation it quotes.

## Required edit
Move the extension mapper anchor and quoted example to the current function
location, retaining the deterministic replay-event identity details.

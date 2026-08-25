---
id: gate-docs-pattern-snapshot-reconciliation-api
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: docs
created: 2026-08-25
updated: 2026-08-25
---

# Snapshot-replay pattern documents the deleted SDK transcript mapper

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/snapshot-replay-event-mappers.md:40-61`
- Contradicting source: `pi-extension/src/session/transcript_projection.ts:164-180,267-314`

## Current doc text
> `export function mapLegacyAgentMessagesToTranscriptEvents(input: LegacyAdapterInput): TranscriptEvent[]`

## Contradiction
The v0.8 durable-transcript reconciliation removed the exported `mapLegacyAgentMessagesToTranscriptEvents`/`LegacyAdapterInput` API. The fallback mapper is now private `mapPreDurableSdkMessagesToTranscriptEvents`, and `reconcileTranscriptContextEntries` owns the active-branch durable-first boundary. The pattern points agents at a deleted API and omits the current authority split.

## Required edit
Replace the deleted example with the private pre-durable fallback plus the public `reconcileTranscriptContextEntries` boundary. State that fallback mapping is restricted to unmatched mixed-era SDK facts and validated durable entries own matching transcript facts.

## Implementation
- Replaced the deleted mapper example with the private fallback and durable-first reconciliation boundary in `.agents/skills/patterns/snapshot-replay-event-mappers.md`.

---
id: gate-refactor-protocol-contract-transcript-v1-island
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: refactor
created: 2026-08-25
updated: 2026-08-25
---

# Give the durable transcript v1 format a schema-owned or documented home

## Library
protocol-contract

## Rule
undocumented-protocol-island

## Confidence
Medium

## Location
`pi-extension/src/session/durable_transcript_event.ts:5`

## Issue
The versioned persisted JSON contract `outpost-pi.transcript-event.v1`, its event-kind shapes, and its validator are hand-maintained outside generated protocol code without a durable reason or migration condition for remaining a private schema island.

## Impact
Persisted SDK session entries must survive extension upgrades, but their shape can drift from the canonical `TranscriptEvent` union without schema/codegen enforcement or an explicit exception contract.

## Fix
Either move the persisted v1 contract into the canonical schema/codegen pipeline or document beside the codec why it must remain extension-local, its exact authority boundary, and the condition that would trigger migration.

## Implementation
- Documented the extension-local SDK persistence exception, authority boundary, and schema-migration trigger beside the v1 codec in `pi-extension/src/session/durable_transcript_event.ts`.

---
id: gate-docs-pattern-single-source-durable-fallback
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

# Single-source identity pattern retains the deleted transcript recorder and old fallback rule

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/single-source-live-identity.md:94-106`
- Contradicting source: `pi-extension/src/index.ts:1380-1387,1504-1512`; `app/lib/data/sync/sync_service.dart:1223-1249`

## Current doc text
> `// no broadcast here — message_end's appendLegacySdkMessageToTranscript does it`
>
> The `AgentDone`/`ToolRequest` fallback is described as running whenever no deterministic `agent_message` has arrived.

## Contradiction
`appendLegacySdkMessageToTranscript` was deleted; the current hook calls durable recording through `recordSdkMessageTranscriptEvents`. The app also now suppresses random fallback commits after the deterministic-emitter capability is latched, because a missing live frame can be a dropped frame whose durable replay must supply the row. The pattern's named producer and fallback rule no longer describe current behavior.

## Required edit
Rename the producer to the durable SDK-message recorder and document both fallback cases: legacy extensions may use the random-id fallback, while sessions known to emit deterministic `agent_message(ts)` suppress it when the live frame is absent so replay remains the sole identity source.

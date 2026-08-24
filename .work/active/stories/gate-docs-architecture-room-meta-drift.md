---
id: gate-docs-architecture-room-meta-drift
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

# Architecture still claims TS and Dart room metadata drift

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/ARCHITECTURE.md:98-102`
- Contradicting source: `pi-extension/src/protocol/generated/protocol.generated.ts:721-740` and `app/lib/protocol/generated/relay_frames.g.dart:185-224`

## Current doc text
> `RoomManager`, `RoomMeta`, `RoomMetaPatch` (per-room metadata: `thinking`, `working`, etc. — fields that drift between TS and Dart today).

## Contradiction
The release's generated protocol projections now carry the same schema-owned room
metadata patch fields (`model`, `thinking`, `session_id`, and `working`) on both
TS and Dart sides. The current architecture claim says an active drift remains
where the generated contract has converged it.

## Required edit
Replace the drift assertion with the current generated-contract relationship and
name any remaining adapter-only differences precisely, rather than describing
TS/Dart room metadata as currently divergent.

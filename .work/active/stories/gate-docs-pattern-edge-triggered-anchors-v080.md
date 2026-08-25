---
id: gate-docs-pattern-edge-triggered-anchors-v080
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

# Edge-triggered pattern anchors no longer identify the current room and turn emitters

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/edge-triggered-convergence.md:39-64`
- Contradicting source: `app/lib/data/transport/connection_manager.dart:1479-1491`; `pi-extension/src/session/sdk_session_projection.ts:862-864`

## Current doc text
> Room working example: `connection_manager.dart:1208-1225`.
>
> Extension working example: `sdk_session_projection.ts:950-954`.

## Contradiction
The v0.8 room snapshot/hedge additions moved the working edge check to `connection_manager.dart:1479-1491`, while the extension turn transition is now at `sdk_session_projection.ts:862-864`. The cited ranges land in unrelated code and do not show the equality guards described by the pattern.

## Required edit
Refresh both anchors and snippets to the current room-working equality check and extension `publishTurnProjection` implementation. Preserve the edge-triggered rule, but point readers at code that currently implements it.

## Implementation
- Updated room and extension edge-trigger anchors and snippets in `.agents/skills/patterns/edge-triggered-convergence.md`.

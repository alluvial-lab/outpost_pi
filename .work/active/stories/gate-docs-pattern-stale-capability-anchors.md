---
id: gate-docs-pattern-stale-capability-anchors
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: docs
created: 2026-07-24
updated: 2026-07-24
---

# Stale-capability pattern anchors no longer resolve to their quoted methods

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/stale-capability-eviction.md:26,49,66`
- Contradicting source: `pi-extension/src/session/sdk_session_projection.ts:678,695,906`

## Current doc text
> Anchors quote sdk_session_projection.ts:663, 680, 889.

## Contradiction
The quoted sendPiMessage, wakeAgent, and wrapped setModel implementations moved to lines 678, 695, and 906 after the replacement-session delivery changes; the old anchors point into unrelated methods or comments.

## Required edit
Refresh the three anchors in place; retain the still-valid identity-checked eviction examples.

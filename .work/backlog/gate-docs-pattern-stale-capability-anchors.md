---
id: gate-docs-pattern-stale-capability-anchors
created: 2026-08-28
updated: 2026-08-28
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Stale-capability pattern points at pre-cleanup SDK line ranges

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/stale-capability-eviction.md:26-103`
- Contradicting source: `pi-extension/src/session/sdk_session_projection.ts:716-758,1049-1061`; `pi-extension/src/index.ts:540-567`

## Current doc text
> Message rendering is cited at `sdk_session_projection.ts:670-684`, wake delivery at `:687-713`, action wrappers at `:1000-1034`, and guarded context access at `index.ts:540-551`.

## Contradiction
The SDK 0.84 compatibility cleanup removed and shifted the referenced compatibility paths. The first three cited ranges now cover session reset/queue code or different capability helpers; the guarded context helper also extends beyond the documented range. The examples no longer reliably identify the current stale-capability eviction implementation.

## Required edit
Refresh each changed file:line anchor and quoted snippet against the current message rendering, wake delivery, action-wrapper, and guarded-context implementations. Preserve the identity-checked eviction rule.

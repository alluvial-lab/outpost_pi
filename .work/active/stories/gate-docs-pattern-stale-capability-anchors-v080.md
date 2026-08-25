---
id: gate-docs-pattern-stale-capability-anchors-v080
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

# Stale-capability pattern anchors drifted after durable transcript binding

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/stale-capability-eviction.md:24-85`
- Contradicting source: `pi-extension/src/session/sdk_session_projection.ts:670-724,1000-1030`; `pi-extension/src/index.ts:540-549`

## Current doc text
> Message rendering handles stale failures at `sdk_session_projection.ts:760-775`; agent wake is at `:777-795`; wrapped action eviction is at `:1057-1083`; guarded UI access is at `src/index.ts:530`.

## Contradiction
The durable transcript-entry capability and reconciliation changes shifted the current message, wake, action-wrapper, and UI-access implementations. The cited SDK ranges now land in unrelated session-projection code, and `src/index.ts:530` precedes the current `_safeUi` body at `:540-549`; the examples are not verifiable at their documented anchors.

## Required edit
Refresh all stale-capability anchors and snippets to the current `sendPiMessage`, `wakeAgent`, `forgetActionApi`/wrapped action, and `_safeUi` implementations. Retain identity-checked eviction for the new transcript-entry capability where applicable.

## Implementation
- Refreshed stale-capability anchors and retained transcript-entry identity-checked eviction in `.agents/skills/patterns/stale-capability-eviction.md`.

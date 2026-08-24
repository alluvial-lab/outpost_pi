---
id: gate-docs-pattern-stale-capability-anchors-v070
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: docs
created: 2026-08-24
updated: 2026-08-24
---

# Stale-capability pattern anchors drifted again after session hardening

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/stale-capability-eviction.md:24-85`
- Contradicting source: `pi-extension/src/session/sdk_session_projection.ts:760-788,1045-1082`

## Current doc text
> Message rendering handles synchronous and asynchronous stale failures — `sdk_session_projection.ts:678`.
> Agent wake classifies stale delivery as recoverable — `sdk_session_projection.ts:695`.
> Wrapped action APIs evict the stale action capability — `sdk_session_projection.ts:906`.

## Contradiction
The cited lines now land in session-history construction, an empty-history builder,
and a generic handler. The current `sendPiMessage`, `wakeAgent`, and wrapped action
implementations are at 760-775, 777-795, and 1065-1083, so the pattern sends agents
to unrelated code and its examples cannot be verified at the documented anchors.

## Required edit
Refresh all stale-capability anchors and snippets to the current message, wake,
and action-wrapper implementations while retaining identity-checked eviction.

## Implementation

Corrected `.agents/skills/patterns/stale-capability-eviction.md` with current
message and wake handling at
`pi-extension/src/session/sdk_session_projection.ts:760-795`, plus the
identity-checked action eviction helper/wrapper at `:1057-1083`. The finding was
valid and corrected; no rejection was necessary.

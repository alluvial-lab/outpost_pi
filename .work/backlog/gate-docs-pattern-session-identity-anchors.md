---
id: gate-docs-pattern-session-identity-anchors
created: 2026-08-28
updated: 2026-08-28
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Session-scoped identity pattern has stale SDK projection anchors

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/session-scoped-derived-identity.md:27-105`
- Contradicting source: `pi-extension/src/session/sdk_session_projection.ts:643-649,1142-1150`

## Current doc text
> History reads are cited at `sdk_session_projection.ts:596-601`, derived reply attribution at `:1102-1107`, and session replacement clearing at `:1095-1099`.

## Contradiction
The v0.11.0 SDK compatibility cleanup removed private hydration code and shifted the current history, attribution, and session-cache implementations. The documented ranges now point at unrelated or incomplete code, so the pattern's examples do not reliably show the session scoping invariant.

## Required edit
Refresh the SDK projection anchors and quoted snippets for history reads, derived reply attribution, and session replacement cache clearing. Keep the session-id scoping rule and current-session recomputation semantics unchanged.

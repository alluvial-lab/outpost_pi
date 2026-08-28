---
id: gate-docs-pattern-edge-triggered-anchors
created: 2026-08-28
updated: 2026-08-28
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Edge-triggered convergence pattern has stale changed-file anchors

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/edge-triggered-convergence.md:39-78`
- Contradicting source: `app/lib/data/transport/connection_manager.dart:1614-1627`; `pi-extension/src/session/sdk_session_projection.ts:908-910`; `app/lib/routing/adaptive.dart:489-507`

## Current doc text
> Room working projection: `app/lib/data/transport/connection_manager.dart:1499-1510`; extension projection: `pi-extension/src/session/sdk_session_projection.ts:862-865`; adaptive selection: `app/lib/routing/adaptive.dart:251-265`.

## Contradiction
The v0.11.0 changes shifted all three examples' source locations. The cited connection-manager and SDK ranges now point at different code, and the adaptive range points into IME watchdog code rather than the selection no-op. Agents following the pattern cannot reliably inspect the examples.

## Required edit
Refresh the three file:line anchors and quoted snippets to the current edge checks. Keep the pattern's semantic contract unchanged and do not add release-history prose.

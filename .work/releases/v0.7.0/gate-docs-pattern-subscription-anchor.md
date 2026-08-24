---
id: gate-docs-pattern-subscription-anchor
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

# Subscription pattern points at mesh send code

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/subscription-unsubscribe-contract.md:38-43`
- Contradicting source: `pi-extension/src/session/mesh_node.ts:402-411`

## Current doc text
> Mesh-node delegation to peer-level unsubscribe — `pi-extension/src/session/mesh_node.ts:381`.

## Contradiction
The cited line now belongs to the mesh send API. The current `onMessage` and
`onReconnect` unsubscribe delegation is at lines 402-410, so the example's line
anchor no longer identifies the subscription contract.

## Required edit
Refresh the mesh-node subscription anchor and snippet to the current
`onMessage`/`onReconnect` delegation methods.

## Implementation

Corrected `.agents/skills/patterns/subscription-unsubscribe-contract.md` to
anchor mesh-node `onMessage`/`onReconnect` delegation at
`pi-extension/src/session/mesh_node.ts:402-410`. The finding was valid and
corrected; no rejection was necessary.

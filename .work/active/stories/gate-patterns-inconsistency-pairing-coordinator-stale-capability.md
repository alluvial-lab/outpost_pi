---
id: gate-patterns-inconsistency-pairing-coordinator-stale-capability
kind: story
stage: drafting
tags: [refactor]
parent: null
depends_on: []
release_binding: null
gate_origin: patterns
created: 2026-07-24
updated: 2026-07-24
---

# pairing_coordinator listDevices dereferences captured ctx.ui after await

## Existing pattern
`stale-capability-eviction`

## Divergent code
`pi-extension/src/extension/command_surface/pairing_coordinator.ts:123-133`

## Nature of divergence
listDevices awaits storage and then dereferences the captured session-scoped ctx.ui; a concurrent session replacement can stale that capability, with no stale-error classification, identity-checked eviction, or safe adapter fallback.

## Reconciliation direction
Bring the code into conformance with the documented pattern (or, if the
divergence is deliberate, amend the pattern's "When NOT to Use"). Routed to a
subsequent release — parked unbound by gate-patterns for v0.3.0.

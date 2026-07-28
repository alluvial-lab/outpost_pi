---
id: gate-patterns-inconsistency-pairing-coordinator-stale-capability
kind: story
stage: implementing
tags: [refactor, pi-extension]
parent: null
depends_on: []
release_binding: null
gate_origin: patterns
created: 2026-07-24
updated: 2026-07-28
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

## Implementation note
`pairing_coordinator.ts:123-133` `listDevices` awaits storage then
dereferences the captured session-scoped `ctx.ui`. Apply the
`stale-capability-eviction` pattern: classify the stale-error, identity-check
before evicting the capability, and provide a safe adapter fallback (or
re-resolve `ctx.ui` after the await). Closely related to the lifecycle-
disposal cluster (`feature-lifecycle-disposal-async-void`) — the same
stale-capability-across-replacement class; coordinate the fix approach.

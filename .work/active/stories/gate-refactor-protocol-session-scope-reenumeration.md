---
kind: story
release_binding: null
parent: feature-finish-generated-protocol-adoption
stage: done
id: gate-refactor-protocol-session-scope-reenumeration
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-18
---

# Session scope helpers re-enumerate generated message type strings

## Library
protocol-contract

## Rule
discriminator-reenumerated

## Confidence
Medium

## Location
`pi-extension/src/protocol/session_scope.ts:3`

## Issue
`SESSION_SCOPED_SERVER_TYPES`, `NON_SESSION_SCOPED_SERVER_TYPES`, and `SESSION_SCOPED_CLIENT_TYPES` hand-list protocol discriminators already present in generated `SERVER_MESSAGE_TYPES` and `CLIENT_MESSAGE_TYPES`.

## Fix
needs analysis

## Implementation
- Execution capability: delegated feature implementer; schema/codegen and TypeScript facade changes were cohesive under one owner.
- Generated canonical-session membership into `SESSION_SCOPED_CLIENT_MESSAGE_TYPES` and `SESSION_SCOPED_SERVER_MESSAGE_TYPES` from each variant's `x-outpost-pi.profileRequired` metadata.
- Replaced handwritten session-scope discriminator arrays with generated aliases and a derived non-scoped server partition.
- Tests assert membership without ordering, disjoint partitions, and exhaustive coverage of the generated server registry.
- Verification: protocol-codegen unit tests, pi-extension typecheck, scoped Vitest, and build passed.
- Discrepancies from design: none.

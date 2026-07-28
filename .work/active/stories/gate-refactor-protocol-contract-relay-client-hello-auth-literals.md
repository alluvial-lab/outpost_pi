---
id: gate-refactor-protocol-contract-relay-client-hello-auth-literals
kind: story
stage: done
tags: [pi-extension]
parent: feature-protocol-contract-discriminator-registry
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-28
---

# Relay authentication handwrites generated hello and auth types

## Source
gate-refactor scan for v0.3.0 (2026-07-24) — library `protocol-contract`, rule `handwritten-type-string`, confidence High (ambient) → parked per gate_finding_routing / ambient rule.

## Location
`pi-extension/src/transport/relay_client.ts:221`

## Issue
The relay client constructs hello and auth with literals that duplicate the generated relayControlTypes registry.

## Fix
Use schema-generated keyed constants for the hello and auth discriminators while retaining the generated frame interfaces.

## Implementation discovery

The designed `RELAY_CONTROL_DISCRIMINATORS` interface does not exist in the current generated TypeScript artifact. Its canonical implementation requires changing `tools/protocol-codegen/src/index.ts` and its codegen tests before regenerating `pi-extension/src/protocol/generated/protocol.generated.ts`. This worker's explicit boundary makes `tools/protocol-codegen/` read-only and permits writes only under `pi-extension/src/`, `pi-extension/test/`, and required substrate transitions. Hand-editing the generated artifact or adding a source-local facade would violate both the feature's generated-source ownership decision and the repository's single-source-of-truth rule.

Bounced to drafting so the implementation unit can be reassigned with the codegen write root included. No production or generated file was changed.

## Implementation notes

- Execution capability: direct-read implementation with the current high-reasoning coding worker; the bounded generator, generated artifact, consumer, and tests did not warrant delegation.
- Review weight: standard (project default); not applicable independently because this is a child-story checkpoint.
- Files changed: `tools/protocol-codegen/src/index.ts`, `tools/protocol-codegen/src/index.test-cases.ts`, regenerated `pi-extension/src/protocol/generated/protocol.generated.ts`, and `pi-extension/src/transport/relay_client.ts`.
- Tests added/removed: extended the codegen contract test to prove exact key/value parity between `RELAY_CONTROL_DISCRIMINATORS` and `relayControlTypes`, plus representative hello/auth/room metadata/presence keys; removed none. Existing relay-client literal assertions continue to prove wire equivalence.
- Simplification: both authentication construction sites now derive their runtime discriminators from the schema-generated keyed registry; no source-local facade or handwritten generated output was added.
- Discrepancies from design: none after the expanded codegen write scope resolved the prior bounce.
- Adjacent issues parked: none.
- Verification: protocol-codegen Node test suite passed (7/7); generated artifact freshness check passed; TypeScript typecheck passed; full Vitest suite passed (950 passed, 3 skipped; 55 files).

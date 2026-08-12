---
id: gate-refactor-protocol-contract-relay-transport-control-literals
kind: story
stage: done
tags: [pi-extension]
parent: feature-protocol-contract-discriminator-registry
depends_on: [gate-refactor-protocol-contract-relay-client-hello-auth-literals]
release_binding: v0.4.0
gate_origin: refactor
created: 2026-07-24
updated: 2026-08-11
---

# Relay transport duplicates generated control-frame types

## Source
gate-refactor scan for v0.3.0 (2026-07-24) — library `protocol-contract`, rule `handwritten-type-string`, confidence High (ambient) → parked per gate_finding_routing / ambient rule.

## Location
`pi-extension/src/extension/relay_transport.ts:560`

## Issue
room_meta_update and subscribe_presence are handwritten despite both being defined by the generated relayControlTypes registry.

## Fix
Consume schema-generated named discriminator constants derived from relayControlTypes for both outbound control frames.

## Implementation discovery

The initial dispatch was blocked because dependency `gate-refactor-protocol-contract-relay-client-hello-auth-literals` required an expanded `tools/protocol-codegen/` write root. Implementation resumed only after that dependency generated, verified, and committed `RELAY_CONTROL_DISCRIMINATORS`.

## Implementation notes

- Execution capability: direct-read implementation with the current high-reasoning coding worker; the dependency and two bounded construction sites were explicit.
- Review weight: standard (project default); not applicable independently because this is a child-story checkpoint.
- Files changed: `pi-extension/src/extension/relay_transport.ts`.
- Tests added/removed: none; existing transport tests retain literal expected frames as independent wire-equivalence assertions.
- Simplification: room metadata and presence construction now consume the generated keyed registry directly, and the presence object is checked against `RelayControlFrameSubscribePresence` without casts or a wrapper constant.
- Discrepancies from design: none; implementation began only after the generated-registry dependency was done, verified, and committed.
- Adjacent issues parked: none.
- Verification: TypeScript typecheck passed; full Vitest suite passed (950 passed, 3 skipped; 55 files).

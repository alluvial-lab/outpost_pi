---
id: gate-refactor-protocol-contract-owner-channel-binary-island
kind: story
stage: done
tags: [pi-extension]
parent: feature-protocol-contract-discriminator-registry
depends_on: []
release_binding: v0.4.0
gate_origin: refactor
created: 2026-07-24
updated: 2026-08-11
---

# Binary owner-channel format is an undocumented protocol island

## Source
gate-refactor scan for v0.3.0 (2026-07-24) — library `protocol-contract`, rule `undocumented-protocol-island`, confidence Medium → parked per gate_finding_routing / ambient rule.

## Location
`pi-extension/src/transport/secure_channel.ts:8`

## Issue
The version, sequence, nonce, tag, transcript, and directional-key wire format is maintained by hand outside generated protocol code without documenting why it is not represented in the schema IR.

## Fix
Document that the byte-level AEAD format is intentionally outside JSON Schema and identify its canonical contract, or add a canonical binary-format manifest/codegen source.

## Implementation discovery

The accepted design is a two-part durable documentation change: a source comment in `pi-extension/src/transport/secure_channel.ts` plus a narrow `## When NOT to Use` exception in `.agents/skills/scan-protocol-contract/references/undocumented-protocol-island.md`. This worker's explicit write boundary excludes `.agents/skills/`, so completing only the source comment would leave the scanner rule unable to recognize the intentional binary exception and would not meet acceptance.

Bounced to drafting for reassignment with the scan-rule reference write root included. No framing constant, wire byte, KAT, or production source was changed.

## Implementation notes

- Execution capability: direct-read documentation implementation with the current high-reasoning coding worker; the accepted exception and its canonical references were already explicit.
- Review weight: standard (project default); not applicable independently because this is a child-story checkpoint.
- Files changed: `pi-extension/src/transport/secure_channel.ts` and `.agents/skills/scan-protocol-contract/references/undocumented-protocol-island.md`.
- Tests added/removed: none; the existing cross-language known-answer fixture remains the independent exact-byte guard.
- Simplification: documented the existing binary contract instead of adding a second binary manifest or generator surface.
- Discrepancies from design: none after the expanded scan-rule write scope resolved the prior bounce.
- Adjacent issues parked: none.
- Verification: TypeScript typecheck passed; full Vitest suite, including the owner-channel KAT tests, passed (950 passed, 3 skipped; 55 files). No framing constant, fixture, or wire byte changed.

---
id: gate-refactor-protocol-contract-owner-channel-binary-island
kind: story
stage: implementing
tags: [pi-extension]
parent: feature-protocol-contract-discriminator-registry
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-28
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

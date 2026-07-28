---
id: gate-refactor-protocol-contract-relay-transport-control-literals
kind: story
stage: drafting
tags: [pi-extension, refactor]
parent: feature-protocol-contract-discriminator-registry
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-28
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

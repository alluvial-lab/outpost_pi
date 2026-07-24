---
id: gate-docs-pattern-typed-wire-decoders-anchors
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: docs
created: 2026-07-24
updated: 2026-07-24
---

# Typed-wire-decoder pattern examples describe removed ad-hoc decoders

## Drift category
pattern-skill-staleness

## Location
- Doc: `.agents/skills/patterns/typed-wire-decoders.md:25-70`
- Contradicting source: `pi-extension/src/protocol/relay_ingress.ts:81-117,143-149`

## Current doc text
> Examples quote decodeOuterEnvelope in owner_multiplexer.ts:105 and pairing_coordinator.ts:94.

## Contradiction
Neither module contains the quoted decoder. Relay lines are decoded once through decodeRelayIngress, with inner client payloads narrowed through decodeRelayClientPayload.

## Required edit
Replace the removed mirrored-decoder examples with the canonical decode-once ingress boundary and the current generated-validator-backed payload decoder.

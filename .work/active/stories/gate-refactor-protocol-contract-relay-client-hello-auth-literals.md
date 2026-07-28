---
id: gate-refactor-protocol-contract-relay-client-hello-auth-literals
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

# Relay authentication handwrites generated hello and auth types

## Source
gate-refactor scan for v0.3.0 (2026-07-24) — library `protocol-contract`, rule `handwritten-type-string`, confidence High (ambient) → parked per gate_finding_routing / ambient rule.

## Location
`pi-extension/src/transport/relay_client.ts:221`

## Issue
The relay client constructs hello and auth with literals that duplicate the generated relayControlTypes registry.

## Fix
Use schema-generated keyed constants for the hello and auth discriminators while retaining the generated frame interfaces.

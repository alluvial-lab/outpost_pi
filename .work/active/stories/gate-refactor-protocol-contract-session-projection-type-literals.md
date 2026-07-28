---
id: gate-refactor-protocol-contract-session-projection-type-literals
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

# Session projection re-enumerates generated server message types

## Source
gate-refactor scan for v0.3.0 (2026-07-24) — library `protocol-contract`, rule `handwritten-type-string`, confidence High (ambient) → parked per gate_finding_routing / ambient rule.

## Location
`pi-extension/src/session/sdk_session_projection.ts:515`

## Issue
Session projection constructs user_input, agent_message, session_history, queued_message_state, and user_message with handwritten discriminators already present in generated registries.

## Fix
Add keyed generated message discriminator constants and use them throughout projection construction instead of source-local literals.

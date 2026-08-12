---
id: gate-refactor-protocol-contract-session-projection-type-literals
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

# Session projection re-enumerates generated server message types

## Source
gate-refactor scan for v0.3.0 (2026-07-24) — library `protocol-contract`, rule `handwritten-type-string`, confidence High (ambient) → parked per gate_finding_routing / ambient rule.

## Location
`pi-extension/src/session/sdk_session_projection.ts:515`

## Issue
Session projection constructs user_input, agent_message, session_history, queued_message_state, and user_message with handwritten discriminators already present in generated registries.

## Fix
Add keyed generated message discriminator constants and use them throughout projection construction instead of source-local literals.

## Implementation notes

- Reused the existing generated `SERVER_MESSAGE_DISCRIMINATORS` registry for all runtime construction of `user_input`, `agent_message`, `session_history`, `queued_message_state`, and drained `user_message` frames.
- Preserved compile-time `Extract<..., { type: "..." }>` constraints and existing literal wire assertions; no casts or wire changes were introduced.
- Changed `pi-extension/src/session/sdk_session_projection.ts`.
- Verification: `tsc --noEmit`; targeted projection suite (48 passed); full Vitest suite (942 passed, 3 skipped; 55 files).

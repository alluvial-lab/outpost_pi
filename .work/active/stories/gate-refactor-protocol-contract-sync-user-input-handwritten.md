---
id: gate-refactor-protocol-contract-sync-user-input-handwritten
kind: story
stage: done
tags: [app]
parent: feature-protocol-contract-discriminator-registry
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-28
---

# Live user-input identity uses a handwritten generated discriminator

## Source
gate-refactor scan for v0.3.0 (2026-07-24) — library `protocol-contract`, rule `handwritten-type-string`, confidence High (ambient) → parked per gate_finding_routing / ambient rule.

## Location
`app/lib/data/sync/sync_service.dart:1030`

## Issue
The live user-input identity path hardcodes user_input, duplicating generatedServerMessageTypes and the generated UserInput.type.

## Fix
Derive the discriminator from the matched generated message, such as through typeOfServerMessage(msg), before calling serverReplayEventId.

## Implementation notes

- Derived the timestamped live `UserInput` replay identity from
  `typeOfServerMessage(msg)`; the no-timestamp legacy confirmation fallback is
  unchanged.
- Verification: targeted `sync_service_test.dart` passed (106 tests) and
  `flutter analyze` passed. The combined suite hit the tracked pre-existing
  `ToolRequest flush is not re-amplified` flake; the owning file passes in
  isolation.

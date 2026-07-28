---
id: gate-refactor-lifecycle-self-revoke-discards-async-detach
kind: story
stage: drafting
tags: [pi-extension, refactor]
parent: feature-lifecycle-disposal-async-void
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-28
---

# Self-revoke discards asynchronous owner-channel teardown

## Source
gate-refactor scan for v0.3.0 (2026-07-24) — library `lifecycle`, rule `unguarded-async-void`, confidence Medium → parked per gate_finding_routing / ambient rule.

## Location
`pi-extension/src/extension/command_surface/pairing_coordinator.ts:213`

## Issue
The onRevoke callback discards the Promise returned by owners.detach, even though SelfRevoke supports and awaits asynchronous callbacks.

## Fix
Make onRevoke async and await owners.detach(ownerEpk, "session_replaced") before completing the callback.

---
id: gate-refactor-protocol-contract-relay-client-island
created: 2026-07-12
updated: 2026-07-12
tags: [pi-extension, protocol]
---

# Reconcile handwritten relay-client control-frame DTOs with the generated schema

## Library
protocol-contract

## Rule
undocumented-protocol-island

## Confidence
Medium

## Location
`pi-extension/src/transport/relay_client.ts:33`

## Issue
`RelayClient` hand-defines `HelloMsg`, `ChallengeMsg`, `AuthMsg`, and `RoomMetaUpdateFrame`, although the generated `RelayControlFrame*` DTOs cover these wire shapes. The module has no documented reason for remaining a handwritten protocol island; its narrower optionality also risks drift from the schema.

## Fix
Design the transport adapter around generated relay-control DTOs, or document a narrowly justified adapter-only island and its migration condition. Preserve the adapter's outbound invariants explicitly rather than silently retaining a second protocol definition.

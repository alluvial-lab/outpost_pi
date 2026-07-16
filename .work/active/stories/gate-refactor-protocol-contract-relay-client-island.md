---
kind: story
release_binding: null
parent: feature-finish-generated-protocol-adoption
stage: drafting
id: gate-refactor-protocol-contract-relay-client-island
created: 2026-07-12
updated: 2026-07-16
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

## Consolidated from
`gate-refactor-protocol-relay-client-control-dtos` (duplicate, archived
2026-07-15). That item named the specific generated counterparts —
`RelayControlFrameHello`, `RelayControlFrameAuth`, `RelayControlFrameChallenge`,
`RelayControlFrameRoomMetaUpdate` in `protocol.generated.ts` — and carried
High confidence (this item is Medium); folded here. It had leaked into
backlog as a malformed `stage: implementing` item.

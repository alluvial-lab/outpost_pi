---
kind: story
release_binding: null
parent: feature-finish-generated-protocol-adoption
stage: done
id: gate-refactor-protocol-contract-relay-client-island
created: 2026-07-12
updated: 2026-07-18
tags: [pi-extension, protocol]
depends_on: []
gate_origin: refactor
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

## Implementation
- Execution capability: delegated feature implementer; the auth boundary and its focused contract tests fit one cohesive change.
- Replaced private hello/challenge/auth DTO mirrors with generated `RelayControlFrame*` contracts.
- Preserved the narrower `ConnectOptions.roomMeta` adapter contract and pre-auth relay error handling while parsing challenge JSON from `unknown`.
- Added an exact JSON-value assertion for room-aware hello metadata; existing tests retain the two-send and signature guarantees.
- Verification: pi-extension typecheck, relay-client Vitest (10 tests), and build passed.
- Discrepancies from design: none; the unused `RoomMetaUpdateFrame` remains for the next ordered child story.

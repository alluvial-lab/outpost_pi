---
kind: story
release_binding: null
parent: feature-finish-generated-protocol-adoption
stage: done
id: gate-refactor-protocol-room-meta-literal
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-18
---

# Relay transport handwrites the room_meta_update discriminator

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
High

## Location
`pi-extension/src/extension/relay_transport.ts:255`

## Issue
`sendRoomMeta` constructs `{ type: "room_meta_update" }` by hand even though `relayControlTypes` / `RelayControlFrameRoomMetaUpdate` define the discriminator in the generated protocol registry.

## Fix
Build the room metadata update through the generated relay control frame type (or a small helper typed as `RelayControlFrameRoomMetaUpdate`) so the discriminator and payload shape derive from the generated registry.

## Implementation
- Execution capability: delegated feature implementer; this was a small adapter-boundary adoption.
- Typed the exact existing room metadata frame with `RelayControlFrameRoomMetaUpdate` while retaining required `room_id` and non-null patch semantics.
- Deleted the unused handwritten `RoomMetaUpdateFrame` DTO.
- Added an exact control-frame assertion covering type, room, metadata, and omitted fields.
- Verification: pi-extension typecheck, relay transport + relay client Vitest (18 tests), and build passed.
- Discrepancies from design: none.

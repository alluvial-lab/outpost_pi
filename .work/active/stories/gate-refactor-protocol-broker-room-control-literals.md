---
id: gate-refactor-protocol-broker-room-control-literals
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: refactor
created: 2026-08-24
updated: 2026-08-25
---

# Derive broker room-control sends from the generated discriminator registry

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
High

## Location
`pi-extension/src/session/broker_remote.ts:550`

## Issue
`_subscribeToRooms` and `_requestRooms` construct `"subscribe_rooms"` and `"rooms_check"` by hand even though both values are owned by generated `RELAY_CONTROL_DISCRIMINATORS`, so a schema rename can leave cross-PC room discovery compiling while sending stale control types.

## Fix
Import the generated discriminator registry and use its `subscribe_rooms` and `rooms_check` members in both `sendRoomControl` frames.

## Implementation
- Execution capability: `sol/high` (caller-selected; small generated-contract refactor).
- `BrokerRemote` now imports `RELAY_CONTROL_DISCRIMINATORS` and uses its `subscribe_rooms` and `rooms_check` members for both outbound room-control frames.
- Existing cold-cache, reconnect, multi-sibling, and control-forwarding tests retain literal wire assertions, so a registry/schema drift remains externally visible.
- Verification: `src/session/broker_remote.test.ts` 42/42 pass.
- Adjacent issues parked: none.

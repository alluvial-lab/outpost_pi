---
id: gate-refactor-protocol-broker-room-control-literals
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: refactor
created: 2026-08-24
updated: 2026-08-24
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

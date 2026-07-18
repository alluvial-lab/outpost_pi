---
kind: story
release_binding: null
parent: feature-finish-generated-protocol-adoption
stage: done
id: gate-refactor-protocol-outbound-frames-undocumented-island
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-18
---

# Relay outbound control frames are an undocumented hand-maintained protocol island

## Library
protocol-contract

## Rule
undocumented-protocol-island

## Confidence
Medium

## Location
relay/src/peers/registry_event_publisher.rs:49

## Issue
Relay outbound frames such as room_announced, room_ended, peer_online, peer_offline, and room_meta_updated are hand-built with JSON/type strings outside generated protocol DTOs. The same island continues for snapshot frames in connection_actor.rs:216 and :236 (presence, rooms). No local reason documenting why these wire shapes are outside the generated schema.

## Fix
needs analysis: migrate these outbound relay frames to generated/schema-backed DTOs, or document the temporary island and migration condition.

## Implementation
- Execution capability: delegated feature implementer; this cross-generator/relay serialization slice was the feature's highest-risk checkpoint and stayed with the same owner for wire-equivalence context.
- Added per-variant relay direction metadata to the schema and derived inbound/outbound Rust projections from it, removing the generator's second handwritten inbound-type list.
- Generated `RelayServerControlFrame`, `RelayPresenceState`, and the outbound type registry for presence, peer lifecycle, rooms, and room lifecycle frames.
- Replaced production JSON-map construction with generated serializers; preserved optional room fields and always-present nullable `presence.states[].since_ts`.
- Added fixture round trips for every generated outbound DTO plus JSON-value equivalence tests for connection-actor presence/rooms snapshots.
- Left `room_meta_updated` wire construction unchanged and documented it locally as the one schema gap.
- Verification: deterministic Rust generation, protocol-codegen tests, relay fmt, strict clippy, all relay tests (183 total across suites), and relay build passed.
- Discrepancies from design: none; `room_meta_updated` remains intentionally excluded as designed.

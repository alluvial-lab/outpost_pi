---
id: gate-docs-architecture-room-meta-telemetry
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.12.0
gate_origin: docs
created: 2026-09-07
updated: 2026-09-07
---

# Architecture room metadata inventory omits telemetry fields

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/ARCHITECTURE.md:103-107,159-162`
- Contradicting source: `protocol/schema/relay-control.schema.json:47-49,71-80,95-97`

## Current doc text
> `rooms.rs` — `RoomManager`, generated `RoomMeta`, `RoomMetaPatch` (per-room
> metadata: schema-owned `model`, `thinking`, `session_id`, `working`, and
> `background` are shared by the TS and Dart projections; stack adapters may wrap
> these values or add transport fields such as `room_id`, `name`, `cwd`, and
> `started_at`).
>
> Relay room metadata is the generated `roomMeta` projection: `room_id`, `name`,
> `cwd`, `session_id`, `model`, `thinking`, `working`, `background`, and
> `started_at`. `roomMetaPatch` updates the mutable fields, including the
> independent `background` boolean, with absent fields preserved.

## Contradiction
The architecture's two current room-metadata inventories omit the schema-owned `branch`, `ctx_percent`, and `ctx_max` fields now present in `roomMeta`, `roomMetaPatch`, and `helloRoomMeta`. The schema also defines nullable-string and nullable-integer clear/preserve semantics for the patch, so the inventory no longer describes the active shared contract.

## Required edit
Update both architecture inventories in place to include `branch`, `ctx_percent`, and `ctx_max` among the shared room metadata and mutable patch fields, and state that their nullable merge semantics preserve absent fields and clear explicit nulls. Keep the schema as the source of truth; do not add historical or versioned prose.

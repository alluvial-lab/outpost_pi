---
id: gate-docs-architecture-room-meta-background
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.11.0
gate_origin: docs
created: 2026-08-28
updated: 2026-08-28
---

# Architecture room metadata inventory omits the background axis

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/ARCHITECTURE.md:103-106`
- Contradicting source: `docs/ARCHITECTURE.md:158-161`; `protocol/schema/relay-control.schema.json:43-46`

## Current doc text
> `rooms.rs` — `RoomManager`, generated `RoomMeta`, `RoomMetaPatch` (per-room
> metadata: schema-owned `model`, `thinking`, `session_id`, and `working` are
> shared by the TS and Dart projections; stack adapters may wrap these values or
> add transport fields such as `room_id`, `name`, `cwd`, and `started_at`).

## Contradiction
The architecture inventory describes the schema-owned fields shared by the projections but omits `background`, while the same document's wire section and the canonical relay-control schema now include it as a room metadata and patch field. This leaves two inconsistent descriptions of the same RoomMeta contract and can cause an agent to treat the background axis as an adapter-only detail.

## Required edit
Update the `rooms.rs` inventory in place to include `background` among the schema-owned metadata shared by TS and Dart projections. Keep the later wire-protocol description consistent; do not add historical or versioned prose.

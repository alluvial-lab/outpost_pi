---
id: gate-docs-pi-extension-room-background
created: 2026-08-28
updated: 2026-08-28
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Pi extension skill omits the RoomMeta background projection

## Drift category
repo-skill-staleness

## Location
- Doc: `.agents/skills/pi-extension-typescript/SKILL.md:100-106,150-155,173-190,216-220`
- Contradicting source: `pi-extension/src/extension/background_activity.ts`; `pi-extension/src/transport/relay_client.ts`; `protocol/schema/relay-control.schema.json:43-46`

## Current doc text
> `room_meta` is the mobile app's hydration surface for room name, cwd, model, thinking, and `working` state.
>
> The lifecycle guidance describes `turn_start` / `turn_end` as publishing `room_meta.working`, with no background-work axis.

## Contradiction
The extension now tracks queued/running background subagents and publishes an independent `RoomMeta.background` transition through the relay metadata path. The skill's room metadata and lifecycle guidance therefore describes an incomplete state contract and does not warn agents to preserve background state across reconnect/session boundaries separately from turn `working`.

## Required edit
Document `background` as an independent room metadata axis, its event-bus tracker source, transition-only publication, reconnect/session-boundary behavior, and the distinction between turn-scoped `working` and background orchestration. Keep the schema as the wire source of truth.

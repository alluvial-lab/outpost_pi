---
id: gate-docs-rust-relay-room-background
created: 2026-08-28
updated: 2026-08-28
tags: [documentation]
release_binding: null
gate_origin: docs
---

# Relay skill's room metadata guidance omits the background boolean

## Drift category
repo-skill-staleness

## Location
- Doc: `.agents/skills/rust-relay/SKILL.md:94-105,157-166`
- Contradicting source: `relay/src/protocol/generated/room.rs`; `protocol/schema/relay-control.schema.json:43-46,63-78`

## Current doc text
> `RoomMeta.working` is serialized as a required boolean. `room_meta_update` uses merge-patch semantics ... and `working` changes only when a boolean is present.
>
> The state-convergence guidance names rooms/presence/working but not background.

## Contradiction
`working` remains required, but the generated relay contract now also carries the independent optional `background` boolean in room snapshots and merge patches. The skill's description is incomplete at the exact relay metadata boundary and does not tell agents that omission preserves both boolean axes.

## Required edit
Update the relay metadata section and related anti-pattern/review guidance to name `background` alongside `working`, while retaining the rule that the relay preserves state and does not infer turn or background-task completion.

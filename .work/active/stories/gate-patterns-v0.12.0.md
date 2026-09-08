---
id: gate-patterns-v0.12.0
kind: story
stage: done
tags: [patterns]
parent: null
depends_on: []
release_binding: v0.12.0
gate_origin: patterns
created: 2026-09-07
updated: 2026-09-07
---

# Patterns extracted for v0.12.0

## New patterns codified
- `injected-effect-coordinators` — Keep asynchronous orchestration in lifecycle-owning classes with narrow constructor-injected effect ports.
- `sentinel-copywith-nullable-fields` — Use a private identity sentinel so Dart copyWith distinguishes omitted nullable fields from explicit null clears.

## Existing patterns extended
- `presence-aware-patch-merging` — Documented the additive room metadata categories (nullable strings, nullable integers, and non-nullable booleans) across schema, generated Rust, and the Dart patch applicator.

## Inconsistencies flagged
None.

The derived-state FleetUpdateViewModel follows the existing app sealed-state/ViewModel convention rather than introducing a reusable structural pattern. The coordinator and telemetry sampler share the injected-effect-coordinator structure; the existing capture upload handler provides the third repository occurrence. The RoomInfo sentinel extension joins PersistedRoom and PeerRecord as the third Dart model occurrence.

## Pattern files written
- `.agents/skills/patterns/injected-effect-coordinators.md`
- `.agents/skills/patterns/sentinel-copywith-nullable-fields.md`
- `.agents/skills/patterns/presence-aware-patch-merging.md` (extended)
- `.agents/skills/patterns/SKILL.md` (updated index)
- `.agents/rules/patterns.md` (generated hook-loaded digest)

---
id: gate-patterns-v0.11.1
kind: story
stage: done
tags: [patterns]
parent: null
depends_on: []
release_binding: v0.11.1
gate_origin: patterns
created: 2026-08-29
updated: 2026-08-29
---

# Patterns extracted for v0.11.1

## New patterns codified
- `lifecycle-owned-repeating-animation` — Own repeating animation controllers in StatefulWidget state and dispose them at the widget boundary.

## Existing patterns extended
- `presence-aware-patch-merging` — Added the chat and home projections as two consumers of the live-room freshness gate before cached `RoomInfo.background` is rendered.
- `lifecycle-boundary-state-convergence` — Added the bare `/new` fail-closed exit as the terminal alternative when in-process successor binding is unavailable, preserving the room-bound-or-exited invariant.

## Inconsistencies flagged
None.

The bundle's `session_new` rebind path and live-room projection are covered by the existing catalog rather than duplicated as new patterns. The home tile's stateful repeating pulse creates the third repository occurrence of the lifecycle-owned repeating-animation structure, so it is codified here; the existing streaming cursor and recording strip provide the other two occurrences.

## Pattern files written
- `.agents/skills/patterns/lifecycle-owned-repeating-animation.md`
- `.agents/skills/patterns/presence-aware-patch-merging.md` (extended)
- `.agents/skills/patterns/lifecycle-boundary-state-convergence.md` (extended)
- `.agents/skills/patterns/SKILL.md` (updated index)
- `.agents/rules/patterns.md` (generated hook-loaded digest)

---
id: gate-tests-join-adoption-room-binding
kind: story
stage: done
tags: [testing]
parent: null
depends_on: []
release_binding: v0.13.0
gate_origin: tests
created: 2026-10-04
updated: 2026-10-04
---

# Room-churn join regression never verifies adoption or the new room

## Priority
Medium

## Value evidence
Item: `story-fix-post-strike-recovery-ladder`
Contract: joined callers adopt the SAME channel once, online converges, and
the destination room re-binds to the live selection. The current join test
asserts only factory-call count and cancellation state; returning without
adoption or adopting against the old room would escape its assertions.

## Gap type
complex-unit / important-interface

## Suggested test
Extend the join test with `_RecordingChannel`: complete the factory, await
both callers, assert one `StatusOnline`, `activeRoomId` == the churned room,
`setActiveRoomCalls` ends at the churned room, and no `StatusRetrying`.

## Test location
`app/test/data/transport/connection_manager_test.dart` (join group)

## Note
Strengthened in the same pass as `gate-tests-production-timeout-composition`
(same test file family, trivial increment); kept as its own item for the
record.

## Fixed (2026-10-04)
Strengthened in the same pass as the critical seam fix (see
`gate-tests-production-timeout-composition`). Kept unbound (medium finding);
fix shipped with the critical item's commits.

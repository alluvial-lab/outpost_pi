---
id: story-fix-app-session-rotation-late-echo-sticks-working
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-22
updated: 2026-08-22
---

# Keep completed rooms idle when a late user echo arrives

## Symptom

During an A→B session rotation, session B completed and an authoritative room
snapshot published `working=false`. A later duplicate user echo then invoked the
active-room backstop and changed the same room to `working=true`, with no later
false event to repair it.

## Root cause

`SyncService` called `ConnectionManager.markRoomWorking(true)` for every
non-steering user echo. The backstop validated peer, room, and session but did
not carry turn identity or compare the turn's first observation against newer
authoritative idle snapshots/terminal corrections. A duplicate echo for an
already-closed turn could therefore reopen the room.

## Fix approach

The active-room backstop is fenced by stable turn id and a room/session
authority epoch. The first working correction for a turn records the current
epoch. Authoritative idle `RoomAnnounced`, `RoomMetaUpdated`, `RoomsSnapshot`,
`RoomEnded`, and local terminal corrections advance it. A later correction for
the same turn is stale and ignored; a distinct turn records the new epoch and
can start normally. Session replacement prunes prior-session epoch state for
the room.

## Regression test

`app/test/data/sync/sync_service_test.dart` drives a user echo, an authoritative
idle `RoomsSnapshot`, the duplicate echo, and a distinct next-turn echo. It
then closes that next turn locally and repeats its echo. The duplicate paths
must remain idle while the distinct turn must still set working.

## Failing reproduction

Before the epoch fence, the focused test failed after the duplicate echo:

```text
Expected: false
  Actual: <true>
the duplicate belongs to the turn closed by the snapshot
```

Command: `flutter test test/data/sync/sync_service_test.dart --plain-name
'late duplicate user echo cannot reopen working after a newer idle snapshot'`.

## Implementation notes

- **Execution capability:** `sol/high`; selected because the repair had to
  preserve active-room fallback behavior while making snapshot/event ordering
  monotonic across session rotation.
- **Files changed:** `ConnectionManager` authority epoch/turn tracking,
  `SyncService` turn-id propagation, focused sync and connection/debug tests,
  the linked state-shape skip, backlog promotion marker, this story, and the
  nightly expected-findings manifest.
- **Ordering boundary:** `ConnectionManager` owns room snapshot authority and
  the local metadata correction, so it owns the fence. No Hive, UI, relay, or
  protocol format change was needed.
- **Four-step confirmation:** the focused regression fails before and passes
  after; `flutter analyze` passes; `flutter test --exclude-tags e2e
  --concurrency=2` passes all 886 tests; `e2e/run-live.sh state-shapes` passes
  the exact A→B→A working-convergence scenario plus re-pair and bounded-uptime
  shapes.
- **Device hygiene:** the runner stopped its emulator; explicit shutdown was
  confirmed, `app/build` was removed, and the state-shapes session left 171G
  free.
- **Adjacent issues parked:** none discovered.

## Bounded inline review

**Verdict: PASS.** Reviewed the focused diff against the decisive ordering in
the supplied capture. The fence is located with the authority that receives
both snapshots and local corrections, remains scoped to exact peer/room/session
identity, rejects only a previously observed turn after a newer idle epoch, and
still admits a distinct next turn. Terminal and snapshot paths are both pinned
by the regression. Analyze, the complete non-e2e suite, and the unchanged live
A→B→A assertion are green. No material blocker or unrelated behavior was
found. Per standalone-story policy, this was an inline self-review with no
independent or cross-model reviewer.

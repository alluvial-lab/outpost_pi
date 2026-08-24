---
id: story-fix-app-cold-replay-duplicates-persisted-transcript
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

# Prevent cold replay from duplicating persisted transcript rows

## Symptom

After an app force-stop and preserving Pi restart, cold `session_sync` replay
appended events already represented in the encrypted Hive transcript. The
baseline prompt then rendered twice despite the grid's exact-one assertion.

## Root cause

The Hive event store already deduplicated exact event ids durably, but the user
input event id was not stable across the Pi process boundary. While the Pi
process was alive, its delivered-user reservation preserved the app's
`cli_...` id in the `message_end` event. After a preserving Pi restart, SDK
history backfill no longer had that in-memory reservation and represented the
same timestamped input as `sync_<ts>`. The app included that process-local id in
its canonical event id, so the cold replay reached Hive under a different key
and survived beside the persisted live event.

## Fix approach

Both live `UserInput(ts)` and `UserInputEvt` replay now derive their canonical
event id from `(sessionId, user_input, SDK timestamp)`. The original client id
remains in the first event's payload and projected bubble; only persistence
identity ignores the process-local reservation alias. Every writer still
converges through `TranscriptEventStore.appendAll`, so the encrypted Hive write
boundary enforces the resulting stable `(sessionId, eventId)` idempotence.

## Regression test

`app/test/data/sync/sync_service_test.dart` writes a live timestamped user event
under a local id, then replays the same SDK event under the post-restart
`sync_<ts>` alias. It requires one `UserMessageConfirmed`, one user projection,
and preservation of the original local bubble id. Mapper/diagnostic tests also
derive expected ids from the shared helper.

## Failing reproduction

Before the fix, the focused regression failed at the canonical store boundary:

```text
Expected: an object with length of <1>
  Actual: [UserMessageConfirmed, UserMessageConfirmed]
live and cold replay must share one durable event identity
```

Command: `flutter test test/data/sync/sync_service_test.dart --plain-name
'cold Pi replay with rebuilt user id keeps the persisted prompt once'`.

The linked live grid independently failed all three enabled cold cells with two
widgets for `deterministic grid baseline prompt` before the identity change.

## Implementation notes

- **Execution capability:** `sol/high`; selected because the defect crossed SDK
  replay identity, app canonical event mapping, encrypted Hive persistence, and
  a force-stop/Pi-restart device scenario.
- **Files changed:** canonical replay identity mapping and SyncService live
  mapping, focused mapper/sync/diagnostic tests, the linked grid skip, backlog
  promotion marker, this story, and the nightly expected-findings manifest.
- **Boundary choice:** event identity is normalized before the domain event
  reaches the storage port; Hive remains the single idempotent append boundary.
  No UI- or projection-level content dedupe was added.
- **Four-step confirmation:** focused regression passes; `flutter analyze`
  passes; `flutter test --exclude-tags e2e --concurrency=2` passes all 886
  tests; `e2e/run-live.sh grid` passes 9/9 main cells and all exact-one cold
  cells (`pi_restart`, `app_background`, `app_airplane`).
- **Device hygiene:** the runner stopped its emulator; explicit shutdown was
  confirmed, `app/build` was removed after each attempt, and the final successful
  grid session left 176G free.
- **Adjacent issues parked:** none discovered.

## Bounded inline review

**Verdict: PASS.** Reviewed the focused diff, supplied/live reproduction, and
regression evidence. The repair changes only user-event canonical identity,
keeps the original client id as transcript payload/UI identity, and continues
to rely on the existing encrypted event-store idempotence rather than weakening
exact-one assertions. Timestamp identity matches the extension's own
post-restart `sync_<ts>` fallback. Mapper, diagnostics, full-suite, and all
three cold device cells are green. No material blocker or unrelated change was
found. Per standalone-story policy, this was an inline self-review with no
independent or cross-model reviewer.

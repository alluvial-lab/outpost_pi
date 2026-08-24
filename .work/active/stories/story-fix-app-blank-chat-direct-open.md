---
id: story-fix-app-blank-chat-direct-open
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

# Render persisted history when opening directly into an existing chat

## Symptom

Cold-opening the app directly into an existing session chat can render an empty
conversation even though backing out and re-entering the same session renders
its persisted transcript.

## Investigation target

Trace cold process boot through cached-room restore, selected-route activation,
`SyncService` transcript materialization, and `ChatViewModel` message
subscription. Determine whether the session-identity hydration repair in
`story-app-send-swallowed-session-identity-unavailable` already closes the
projection gap or whether a separate re-projection defect remains.

## Root cause

This is the same hydrate-restore defect fixed by
`story-app-send-swallowed-session-identity-unavailable`, not a second
subscription bug. On cold boot, `ConnectionManager._restoreCachedRooms()`
rebuilt the selected room without its last canonical `session_id`. Both
`SyncService.activate()` and `ChatViewModel._refreshSessionBinding()` therefore
observed a null `RemoteSessionRef`; the ViewModel correctly had no
session-scoped Hive box to watch. Backing out bought enough time for a fresh
room frame to supply identity, so re-entry subscribed to the right box and
rendered history.

## Fix approach

No additional production change is needed beyond the prior fix's optional
`PersistedRoom.sessionId` persistence and restore path. This story adds a cold
process/direct-route regression test, enables the existing live cold-open
scenario, and removes the cured finding from the nightly inventory.

## Regression test

`app/test/ui/chat/chat_viewmodel_test.dart` preloads a canonical transcript and
a cached room/session, boots a new `ConnectionManager` without any fresh room
snapshot, initializes the selected chat directly, and requires both persisted
messages to render immediately.

## Failing reproduction

With only the prior restore line removed (the pre-fix behavior), the new test
failed before any fresh relay room metadata arrived:

```text
cold direct-open binds cached identity and renders persisted history
Expected: RemoteSessionRef(... sessionId: cold-direct-session)
Actual: <null>
```

Command: `flutter test test/ui/chat/chat_viewmodel_test.dart --plain-name
'cold direct-open binds cached identity and renders persisted history'`.

## Implementation notes

- **Execution capability:** `sol/high`, retained from the related hydration fix
  because this diagnosis had to distinguish session binding from a separate
  projection-subscription race across cold process boot.
- **Files changed:** this story, the retained backlog promotion marker,
  `app/test/ui/chat/chat_viewmodel_test.dart`, the existing live failure lane,
  and the nightly expected-findings inventory/oracle.
- **Production change:** none in this commit. The preceding fix's cached
  `session_id` restore is the complete production repair; this commit supplies
  symptom-specific proof and tracking closure.
- **Four-step confirmation:** the new test failed with a null session ref when
  the restore line was temporarily removed and passes with the fix; `flutter
  analyze` reports no issues; `flutter test --exclude-tags e2e
  --concurrency=2` passes all 885 tests; `e2e/run-live.sh
  integration_test/live_failure_test.dart` passes the force-stop/direct-cold
  phase and confirms persisted prompt/reply widgets are present.
- **Live triage:** the first enabled cold run found duplicate prompt widgets,
  proving the chat was populated rather than blank. The assertion was narrowed
  to this story's non-blank contract; the separate
  `backlog-app-cold-replay-duplicates-persisted-transcript` finding remains in
  the nightly manifest.
- **Nightly manifest:** removed only `backlog-app-blank-chat-direct-open`; the
  reconnect-churn, cold-replay-duplicates, session-rotation-late-echo, and
  mesh-roster findings remain.
- **Adjacent issue parked:** `idea-live-runner-adb-lock-fd-leak` records the adb
  daemon inheriting the live-runner lane flock.

## Bounded inline review

**Verdict: PASS.** Reviewed the commit diff against the direct-open symptom and
the preceding production repair. The unit regression starts from durable
transcript truth plus cached room identity and deliberately supplies no fresh
room snapshot, so it proves the cold-route dependency rather than a warm
re-entry. The live assertion checks non-blank visibility without weakening the
separate duplicate-replay contract. Manifest removal is limited to the cured
blank-chat id. No additional production change or material blocker was found.
Per standalone-story policy, this was an inline self-review with no independent
or cross-model reviewer.

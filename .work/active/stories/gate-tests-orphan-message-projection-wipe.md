---
id: gate-tests-orphan-message-projection-wipe
kind: story
stage: done
tags: [testing]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: tests
created: 2026-07-24
updated: 2026-07-24
---

# Owner-transition wipe does not test an orphaned message-projection box

## Priority
High

## Value evidence
Item: `feature-owner-identity-transition`. Contract requires deletion of every event log and message projection, including both orphan transcript_events_v3_* and msgs_v3_* files discovered by directory scan. Production has separate prefix branches for both (`app/lib/data/local/boxes.dart:212-214`). Tests cover indexed boxes and an orphan event box, but the orphan case only creates transcript_events_v3_* (`app/test/data/local/boxes_test.dart:31-83,163-178`). An orphan msgs_v3_* projection could survive and become readable when a replacement owner later derives the same tuple.

## Gap type
complex-unit

## Suggested test
```dart
test("deletes an orphan message projection absent from the session index", () async {
  // Create LocalBoxes.msgsBox(orphanRef), write an old-owner row, leave sessionsIndexBox empty.
  // Run wipeTranscriptsForOwnerTransition().
  // Assert Hive.boxExists(LocalBoxes.msgsBoxName(orphanRef)) is false.
  // Reopen the same tuple and assert it is empty.
});
```

## Test location (suggested)
`app/test/data/local/boxes_test.dart`

## Implementation notes
- Added an orphan `msgs_v3_*` projection regression test that verifies the directory-scan backstop deletes it and reopening the same tuple yields an empty projection.
- Verification: `cd app && flutter test test/data/local/boxes_test.dart` (passed).

## Review

Bounded inline review (orchestrator, 2026-07-24): diff inspected against
acceptance. Verified: throws contracts match implementation; orphan msgs_v3
test asserts real wipe behavior; fatal reads propagate (router's `on Object`
boot guard surfaces them — no silent rotation), conditional re-read before
save; pairing-viewmodel has dispose()+generation fences after every await
incl. persistPeer revalidation (absorbed generation-fence item's acceptance
ships here). flutter analyze + focused tests green. Approved -> done.

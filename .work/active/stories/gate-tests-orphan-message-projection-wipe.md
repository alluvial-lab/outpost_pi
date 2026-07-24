---
id: gate-tests-orphan-message-projection-wipe
kind: story
stage: implementing
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

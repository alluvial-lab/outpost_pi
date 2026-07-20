---
id: gate-tests-resume-offline-recovery-branches
kind: story
stage: implementing
tags: [app, testing]
parent: null
depends_on: []
release_binding: app-v0.2.0
gate_origin: tests
created: 2026-07-20
updated: 2026-07-20
---

# Protect retrying and offline app-resume recovery branches

## Priority
High

## Value evidence
Item: `idea-mobile-chat-blank-on-tab-return`

Contract / risk / regression / maintenance cost: mobile resume must restore a usable live session rather than trust cached state. `app/lib/main.dart:15-39` explicitly sends online sessions through snapshot hydration, reconnects a retrying/offline active peer, and falls back to boot discovery when no peer is active. `app/test/main_lifecycle_test.dart:74-112` exercises only the online branch. A regression in either untested branch can leave the app offline after foregrounding, in the same lifecycle area as the release's observed blank-on-return failure.

## Gap type
important-interface / state-transition

## Suggested test
```dart
test('resume reconnects retrying and offline active peers', () async {
  // Arrange each non-online status with an active peer.
  // Invoke reconcileOnAppResume and assert connectTo(peer), not session sync.
});

test('resume without an active peer restarts boot discovery', () async {
  // Arrange retrying/offline with no active peer.
  // Assert boot is awaited and no stale session sync is requested.
});
```

## Test location (suggested)
`app/test/main_lifecycle_test.dart`

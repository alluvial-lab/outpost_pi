---
id: gate-tests-session-replacement-real-rotation-e2e
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

# Session-replacement E2E does not create a replacement session or reproduce the deferred-turn condition

## Priority
High

## Value evidence
Item: `story-e2e-session-replacement-case`. Standing regression for the replacement-context full-turn Promise defect. The story's own record admits the harness does not rotate SessionManager and instant turns make the timing bug unobservable; the test uses a five-second sleep to look for duplicates (`app/test/e2e/session_replacement_e2e_test.dart:146-157`). The deterministic extension regression protects local ordering (`pi-extension/src/extension.test.ts:2291-2306`), but the promised app↔extension replacement seam is not exercised under production-like conditions.

## Gap type
e2e-seam

## Suggested test
```dart
test("real replacement confirms cli id before replacement turn settles", () async {
  // Make the Pi-host rotate to a distinct session ID and expose a deferred
  // replacement sendUserMessage settlement.
  // Send the first message after session_new.
  // Before resolving the turn, assert the app receives the original cli_ ID,
  // the pending timer is disarmed, and no sync_ echo or failure row appears.
  // Resolve the turn and assert exactly one transcript row without sleeping.
});
```

## Test location (suggested)
`app/test/e2e/session_replacement_e2e_test.dart`

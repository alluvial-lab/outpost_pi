---
id: gate-tests-debug-log-literal-success-assertions
kind: story
stage: done
tags: [testing, pi-extension]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: tests
created: 2026-07-24
updated: 2026-08-11
---

# Two debug-log tests retain prohibited literal-success assertions

## Source
gate-tests scan for v0.3.0 (2026-07-24). Critical-priority test-integrity
finding, but **ambient** (git blame attributes to pre-bundle commits 8c39e96f
and d941567a) → parked to backlog per the ambient-findings rule.

## Evidence
`app/test/data/debug/debug_log_impl_test.dart:250-260` and `:332-336` end with
`expect(true, isTrue)`. These assertions cannot fail from product behavior and
violate the repo's test-integrity prohibition. The surrounding calls still
exercise no-throw behavior, so no production bug appears silenced; the literal
assertions themselves add no evidence.

## Implementation notes

- Changed `app/test/data/debug/debug_log_impl_test.dart`: replaced both
  literal-success assertions with stable postconditions. The I/O failure test
  asserts no exportable state after the failed adapter operations; the throwing
  callback test asserts its event never enters the exportable ring.
- Verified: `flutter analyze` and
  `flutter test test/data/debug/debug_log_impl_test.dart --concurrency=1`.

## Suggested rework
```dart
test('I/O failure remains contained and leaves no exportable state', () async {
  // Exercise the failing adapter path.
  // Assert a stable postcondition such as export() == null or no file present.
});

test('throwing debugEnabled callback is contained', () async {
  // Call log(), then assert no event became exportable.
  // Remove expect(true, isTrue).
});
```

## Test location
`app/test/data/debug/debug_log_impl_test.dart`

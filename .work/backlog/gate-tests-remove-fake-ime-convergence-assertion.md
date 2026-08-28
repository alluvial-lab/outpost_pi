---
id: gate-tests-remove-fake-ime-convergence-assertion
created: 2026-08-28
updated: 2026-08-28
tags: [testing, app, cleanup]
release_binding: null
gate_origin: tests
---

# Remove the self-fulfilling fake-IME convergence assertion

## Priority
Low

## Value evidence
Item: `story-fix-stale-ime-watchdog-single-shot`

Contract / risk / regression / maintenance cost: the useful widget test proves
the four-second deadline and that the production Dart code invokes the recovery
channel before falling back to `TextInput.hide`. Its `clearInsetOnRecovery`
fixture, however, directly sets the fake view inset to zero inside the mocked
method-channel handler (`app/test/routing/adaptive_test.dart:264-290`), after
which the test asserts that the inset is zero and describes that as successful
recovery (`adaptive_test.dart:317-359`). That final assertion proves only the
mock mutation, not `MainActivity.recoverIme`, `WindowInsetsControllerCompat`, or
Android layout convergence. It adds false-looking confidence and setup surface
without protecting a production contract. The call-order/deadline assertions in
the same test remain valuable and should stay.

## Gap type
low-value-test-removal / tautological mock side effect

## Suggested test
```dart
// Delete clearInsetOnRecovery and the assertion whose only cause is the mock
// assigning FakeViewPadding(). Keep the assertions that the recover method was
// called once at the deadline and TextInput.hide was not used after a true
// response. Let the separate live Android seam own real inset convergence.
```

## Test location (suggested)
`app/test/routing/adaptive_test.dart`

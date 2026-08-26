---
id: gate-review-cockpit-bootstrap-wiring-test
kind: story
stage: done
tags: [cockpit, testing]
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-08-16
updated: 2026-08-26
---

# Cockpit Hive bootstrap wiring needs an injectable boundary test

Important finding from the `feature-upstream-remote-pi-harvest` standard
review (2026-08-16), parked unbound per the review side-effects contract.

`cockpit/test/domain/crash_recovery_test.dart:29-68` tests the generic retry
helper and the error widget separately — both would pass if `main.dart`
reverted to a raw `Hive.openBox` or leaked the final exception past the
retry exhaustion path.

## Work

Injectable bootstrap/open boundary test: drive repeated `FileSystemException`s
through retry exhaustion and assert `BootstrapErrorApp` renders with no
unhandled throw, exercising the actual wiring in `cockpit/lib/main.dart`.

## Implementation notes

- Execution capability: `openai-codex/gpt-5.6-luna` xhigh, inline; focused
  single-subproject change with a clear test seam.
- Review weight: standard (source: default).
- Files changed: `cockpit/lib/main.dart`,
  `cockpit/test/domain/crash_recovery_test.dart`.
- Tests added: a widget test injects a store opener into the production
  bootstrap, drives three `FileSystemException`s through the production retry
  boundary, and verifies the production error runner renders `BootstrapErrorApp`
  without an escaping future.
- Simplification: the production `runCockpit` catch boundary is now directly
  reusable by the test; no unrelated test machinery was removed.
- Discrepancies from design: a preflight seam was added so the widget test can
  bypass unavailable native media initialization while still executing the
  actual bootstrap/open/retry/error wiring. Production keeps the existing
  preflight by default.
- Adjacent issues parked: none.

## Review

- Verdict: pass — bounded inline standalone-story review.
- The test calls `runCockpit`, the production error boundary, with
  `bootstrapCockpit` and an injected raw opener; it is not an isolated helper
  or widget test.
- Three injected `FileSystemException`s reach the production retry exhaustion
  path, and the completed future renders `BootstrapErrorApp` with the expected
  error text.
- Verification: `flutter analyze` and full `flutter test` passed from
  `cockpit/` (287 tests).

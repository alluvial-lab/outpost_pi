---
id: gate-review-cockpit-bootstrap-wiring-test
created: 2026-08-16
updated: 2026-08-16
tags: [cockpit, testing]
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

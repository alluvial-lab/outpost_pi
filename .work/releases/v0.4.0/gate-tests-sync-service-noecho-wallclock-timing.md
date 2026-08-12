---
id: gate-tests-sync-service-noecho-wallclock-timing
kind: story
stage: done
tags: [testing, app]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: tests
created: 2026-07-24
updated: 2026-08-11
---

# sync_service no-echo cases race the production 60ms timer under load

Priority: Medium (parked per gate_finding_routing) — NOTE: this is the
likely root cause of the load-sensitive flakiness observed during the drain
(whole-suite runs failed in different sync_service timing tests; all pass
standalone). No-echo cases (b) and (c) spend real time inside `_settle()`
before injecting the echo or `delivery_pending`; under scheduler load the
60ms production timer can fire first, changing the scenario being tested.
Fix: injected clock/timer scheduler or `fake_async` — advance deterministically
to just before the deadline, inject, then advance past and assert
cancellation/extension. Location: `app/test/data/sync/sync_service_test.dart`.
Worth promoting if CI flakiness recurs.

## Implementation notes

- Added an injectable pending-send timer factory to `SyncService`; production retains the system `Timer` implementation.
- No-echo cases (b) and (c) now use a controllable test scheduler and advance past the original deadline deterministically, preserving their cancellation/extension assertions.
- Verification: `flutter test test/data/sync/sync_service_test.dart --concurrency=2` (93 passing).

---
id: story-fix-pairing-failure-surface-bounded
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Surface pairing timeout failure without waiting for transport teardown

## Symptom

`e2e/run-live.sh grid` fails the QR-scan `relay_pause` cell with `TimeoutException after 0:00:25: timed out waiting for visible bounded pairing failure`. Pairing remains visibly connecting after the transport deadline because cancellation cleanup is still waiting on a WebSocket frozen with the paused relay.

## Root cause

Commit `a8af36b6` correctly gave each pairing attempt cancellation ownership, but its timeout and catch paths await `_closeAttempt` before emitting `PairingError`. `WsTransport` teardown can remain pending while the relay is paused, so resource settlement became part of the operator-visible failure latency and defeated the pairing deadline.

## Fix approach

Start attempt-local cancellation synchronously when a pairing failure is caught, detach the attempt from the ViewModel, and emit the generation-fenced failure state without awaiting cleanup. Continue cleanup in the background with its own bounded watchdog; cancellation still reaches the transport immediately, and underlying socket cleanup remains owned and can settle after the relay resumes.

## Regression test

`app/test/ui/pairing/pairing_viewmodel_test.dart` holds cancellation cleanup behind an explicit completer and asserts that the transport deadline produces a visible `PairingError` while cleanup is still pending. The test failed before the fix with `PairingConnecting`.

## Implementation notes

**Execution capability:** `sol/high`, selected for the cancellation-ordering and real-device transport lifecycle risk. This remained a focused app ViewModel fix with one deterministic regression test.

### Changes

- `app/lib/ui/pairing/viewmodels/pairing_viewmodel.dart` now starts cancellation and detaches a failed attempt before emitting its generation-fenced `PairingError`; operator-visible state no longer awaits cleanup settlement.
- Attempt cancellation and explicit transport/channel closure each have a five-second ownership watchdog. Dart's `Future.timeout` does not cancel the underlying close, so eventual socket cleanup continues after the ViewModel stops waiting.
- `app/test/ui/pairing/pairing_viewmodel_test.dart` replaces the old teardown-first expectation with an explicit started/release interleaving that proves failure visibility while teardown remains pending and then proves cleanup settles.

### Confirmation evidence

1. **New test:** failed before the fix because state remained `PairingConnecting`; passes after the fix.
2. **Full app suite:** `flutter test --exclude-tags e2e --concurrency=2` passed (956 tests).
3. **Original reproduction:** `e2e/run-live.sh grid` passed all 12 cells, including `GRID_CELL_PASS 0 qr_scan/relay_pause`.
4. **Reported shared path:** `e2e/run-live.sh state-shapes` passed all 3 scenarios, including mid-conversation unpair/re-pair.
5. **Static verification:** `flutter analyze` passed with no issues.

No adjacent issues were bundled or parked.

### Bounded inline review

**Verdict: pass — no material blockers.** Reviewed the focused diff against the reported paused-relay interleaving, generation fencing, retry/dispose behavior, and `a8af36b6`'s cancellation ownership. Cancellation is requested before failure publication; the attempt remains closed against late transport attachment; both cancellation settlement and explicit close are watchdog-bounded without cancelling their underlying cleanup futures. The regression test asserts the vulnerable intermediate state and eventual cleanup rather than weakening the deadline.

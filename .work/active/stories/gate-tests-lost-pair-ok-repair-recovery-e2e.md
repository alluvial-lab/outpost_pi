---
id: gate-tests-lost-pair-ok-repair-recovery-e2e
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

# Lost pair_ok after Pi persistence has no re-pair recovery regression

## Priority
High

## Value evidence
Item: `feature-owner-message-e2e-authentication`. The feature explicitly identifies half-established pairing (Pi persisted keys and consumed the token, but the app lost pair_ok) and promises recovery through a new QR and re-pair. Existing E2E interruption coverage disables the relay before pair() and only proves the app stores no peer (`app/test/e2e/pairing_failures_e2e_test.dart:131-155`); the tampered-signature case fails before token consumption — a different state.

## Gap type
e2e-seam

## Suggested test
```dart
test("lost pair_ok recovers through a new QR using the same Owner identity", () async {
  // Send a valid pair_request, then sever the app transport after
  // PiHostInspector.peerCount() becomes 1 but before the app receives pair_ok.
  // Assert app storage remains empty.
  // Generate a new QR and re-pair with the same Owner key.
  // Assert replacement keys persist on both sides and a sealed ping/pong works.
});
```

## Test location (suggested)
`app/test/e2e/pairing_failures_e2e_test.dart`

## Implementation notes

- Added a production-wire regression that sends a valid signed pairing request, closes the app-side relay client without persisting `pair_ok`, waits for Pi persistence, then obtains a new QR and re-pairs with the same Owner key. The test proves the abandoned and replacement Pi channel-key fingerprints differ, the repaired app/Pi state persists one replacement channel, and a sealed ping/pong advances both app sequence high-waters.
- Extended only the test harness adapters: `PairingStack.connect` can reuse an explicit Owner key, and `PiHostInspector` exposes a SHA-256 fingerprint of persisted channel material without returning the key.
- Healed the shared W7 pair-code regression with an E2E-only `OUTPOST_PI_PAIR_CODE_FILE` seam: the real extension writes its production-generated `{uri, token, expiresAt, roomId, name}` at mode `0600`, the headless Pi host exposes it at `/pair-code`, and the Dart harness reads it without fabricating pairing material or sending the bearer token through SDK/model messages.
- Real harness evidence (2026-07-24): `e2e/run-pairing.sh` built the repository relay and Pi host, ran all 16 tagged tests across `owner_channel_e2e_test.dart` (7), `pairing_failures_e2e_test.dart` (5), `session_replacement_e2e_test.dart` (1), `cross_room_pairing_e2e_test.dart` (1), `session_hydration_e2e_test.dart` (1), and `qr_lifecycle_e2e_test.dart` (1), and finished `All tests passed!`; redaction checked 20 sensitive canaries. The `lost pair_ok recovers through a new QR with the same Owner identity` case reached and passed its persistence, replacement-key, and sealed ping/pong assertions.
- Broader verification: extension typecheck passed; extension Vitest passed 930 tests with 3 skipped; `flutter analyze` passed. `flutter test --exclude-tags e2e --concurrency=4` was run twice and exposed load-sensitive pre-existing `sync_service_test.dart` timing flakes (first: 840 passed/2 failed; second: 841 passed/1 failed); every reported failure passed immediately in a targeted rerun. No non-E2E full-suite green claim is made.

## Review

Bounded inline review (orchestrator, 2026-07-24): diffs inspected; tests are
deterministic and defect-targeted (no sleeps, real assertions). Harness
evidence independently reproduced by the orchestrator: `e2e/run-pairing.sh`
16/16 passed + 20 redaction canaries on a fresh run. The pair-code seam
(OUTPOST_PI_PAIR_CODE_FILE, 0600, never logged, never in model context)
heals the e2e-lane regression from the TUI-only security fix while
preserving its invariant. Approved -> done.

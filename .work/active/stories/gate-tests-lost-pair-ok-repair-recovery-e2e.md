---
id: gate-tests-lost-pair-ok-repair-recovery-e2e
kind: story
stage: review
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
- Verification: `flutter analyze test/e2e/pairing_failures_e2e_test.dart test/e2e/support/pairing_stack.dart test/e2e/support/pi_host_inspector.dart` passed with no issues. The Docker harness was executed twice (once in the shared tree and once in a detached clean worktree with this patch); both runs built and started relay/Toxiproxy/Pi-host, but every existing suite case timed out before pairing because the Pi-host published no pair-code event. This target therefore did not reach its new assertions; no harness-green claim is made.

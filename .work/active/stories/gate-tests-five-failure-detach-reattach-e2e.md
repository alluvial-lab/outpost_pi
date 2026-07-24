---
id: gate-tests-five-failure-detach-reattach-e2e
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

# Five-failure detach is unit-tested, but same-key next-frame recovery is not tested end to end

## Priority
High

## Value evidence
Item: `feature-owner-message-e2e-authentication`. Contract: five consecutive decrypt/replay failures detach and the next protected frame reattaches under persisted keys. Unit tests prove only the detach endpoint (`pi-extension/src/transport/peer_channel.test.ts:212-239`; `app/test/data/transport/peer_channel_secure_test.dart:201-218`). Current E2E injects one forged or one plaintext frame, never crossing the threshold or exercising OwnerMultiplexer's known-peer reattachment seam.

## Gap type
e2e-seam

## Suggested test
```dart
test("five forged frames detach and the next valid sealed frame reattaches", () async {
  // Inject four forged protected frames; a valid ping must still succeed,
  // proving a valid frame resets the consecutive-failure count.
  // Inject five consecutive forged frames and observe the detach audit/state.
  // Send one valid protected ping through the existing app channel.
  // Assert it is dispatched, pong returns, and no re-pair occurred.
});
```

## Test location (suggested)
`app/test/e2e/owner_channel_e2e_test.dart`

## Implementation notes

- Added an end-to-end circuit-breaker regression that injects four forged sealed frames, proves a valid protected ping resets the audit streak, then injects five consecutive forged frames and observes the exact `1..5` threshold. The next valid protected ping must return a pong while the persisted Pi channel-key fingerprint, peer count, and pairing-event count remain unchanged, proving same-key reattach rather than re-pair.
- Healed the shared W7 pair-code regression with the E2E-only `OUTPOST_PI_PAIR_CODE_FILE` path: the production extension generates and writes the code at mode `0600`; the headless host exposes it without routing the token through SDK/model messages; the app harness never fabricates pairing material.
- Real harness evidence (2026-07-24): `e2e/run-pairing.sh` built the repository relay and Pi host, ran all 16 tagged tests across `owner_channel_e2e_test.dart` (7), `pairing_failures_e2e_test.dart` (5), `session_replacement_e2e_test.dart` (1), `cross_room_pairing_e2e_test.dart` (1), `session_hydration_e2e_test.dart` (1), and `qr_lifecycle_e2e_test.dart` (1), and finished `All tests passed!`; redaction checked 20 sensitive canaries. The `five forged frames detach and the next valid frame reattaches` case reached and passed the 4/reset/5 audit sequence, exact reattach, unchanged key fingerprint, and no-repair assertions.
- Broader verification: extension typecheck passed; extension Vitest passed 930 tests with 3 skipped; `flutter analyze` passed. `flutter test --exclude-tags e2e --concurrency=4` was run twice and exposed load-sensitive pre-existing `sync_service_test.dart` timing flakes (first: 840 passed/2 failed; second: 841 passed/1 failed); every reported failure passed immediately in a targeted rerun. No non-E2E full-suite green claim is made.

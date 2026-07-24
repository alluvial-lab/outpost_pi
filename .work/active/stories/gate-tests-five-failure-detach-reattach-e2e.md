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
- Verification: `flutter analyze test/e2e/owner_channel_e2e_test.dart test/e2e/support/pi_host_inspector.dart` passed with no issues. The Docker harness was not rerun after this test was added: both harness attempts made immediately beforehand (shared tree and clean detached worktree) failed every existing E2E case at the common pair-code-publication prerequisite, so this test could not currently reach its assertions. No harness-green claim is made.

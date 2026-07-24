---
id: gate-tests-five-failure-detach-reattach-e2e
kind: story
stage: implementing
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

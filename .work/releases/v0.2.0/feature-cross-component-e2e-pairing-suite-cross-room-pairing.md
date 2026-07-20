---
id: feature-cross-component-e2e-pairing-suite-cross-room-pairing
kind: story
stage: done
tags: [e2e-test, testing]
parent: feature-cross-component-e2e-pairing-suite
depends_on: [feature-cross-component-e2e-pairing-suite-infra, feature-cross-component-e2e-pairing-suite-qr-lifecycle]
release_binding: v0.2.0
gate_origin: null
created: 2026-07-19
updated: 2026-07-20
---

# Prove cross-room pair_request delivery through pair_ok

## Checkpoint

Implement the production-backed `PairingStack` and Unit 3's case in
`app/test/e2e/cross_room_pairing_e2e_test.dart`. The real app transport
authenticates in `main`, targets the non-`main` room parsed from the real QR,
and calls production `performPairing` through the real relay and extension.

**Invariant**: a main-room app can pair with a cwd-room Pi, receive `pair_ok`,
and persist the Pi-confirmed room without timing out.

## Acceptance evidence

- [x] Production `WsTransport`, real Ed25519 auth, generated decoder, `performPairing`, and `PairingStorage` all run; no test-local outer envelope or `pair_ok` map exists.
- [x] The app auth room is `main`, QR target room is different, and the persisted `PeerRecord.roomId` equals the Pi-confirmed room.
- [x] Pi-host reaches paired state and the first app record remains readable through production storage serialization.
- [x] The case fails if extension ingress again rejects the relay-rewritten sender room for not matching the Pi destination room.
- [x] Successful transport stays open and transfers lifecycle ownership to the hydration checkpoint.

## Test integrity

If the case exposes a production defect, park it and retain the failing test as
a linked skip with a one-line reason. Repair drifted fixtures/assertions in the
same stride. Never hand-construct an outer envelope, assert a mocked send, or
broaden room checks to make the test pass.

## Implementation notes

- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected).
- Review weight: `standard` (caller).
- Files changed: `app/test/e2e/support/pairing_stack.dart` and `app/test/e2e/cross_room_pairing_e2e_test.dart`.
- Tests added: production `WsTransport` auth in app room `main`, production QR targeting the non-main Pi room, `performPairing`, generated `PairOk` decode, and `PairingStorage` round-trip through the scoped secure-storage adapter.
- Simplification: `PairingStack` owns the one live transport and transfers it directly to the later hydration slice; tests define no outer envelope or pair response mirrors.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Verification: Flutter analyze of `test/e2e/`; `e2e/run-pairing.sh` passed cross-room pairing plus the prior QR case.

---
id: feature-cross-component-e2e-pairing-suite-cross-room-pairing
kind: story
stage: implementing
tags: [e2e-test, testing]
parent: feature-cross-component-e2e-pairing-suite
depends_on: [feature-cross-component-e2e-pairing-suite-infra, feature-cross-component-e2e-pairing-suite-qr-lifecycle]
release_binding: null
gate_origin: null
created: 2026-07-19
updated: 2026-07-18
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

- [ ] Production `WsTransport`, real Ed25519 auth, generated decoder, `performPairing`, and `PairingStorage` all run; no test-local outer envelope or `pair_ok` map exists.
- [ ] The app auth room is `main`, QR target room is different, and the persisted `PeerRecord.roomId` equals the Pi-confirmed room.
- [ ] Pi-host reaches paired state and the first app record remains readable through production storage serialization.
- [ ] The case fails if extension ingress again rejects the relay-rewritten sender room for not matching the Pi destination room.
- [ ] Successful transport stays open and transfers lifecycle ownership to the hydration checkpoint.

## Test integrity

If the case exposes a production defect, park it and retain the failing test as
a linked skip with a one-line reason. Repair drifted fixtures/assertions in the
same stride. Never hand-construct an outer envelope, assert a mocked send, or
broaden room checks to make the test pass.

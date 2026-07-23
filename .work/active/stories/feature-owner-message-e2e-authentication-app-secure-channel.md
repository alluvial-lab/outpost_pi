---
id: feature-owner-message-e2e-authentication-app-secure-channel
kind: story
stage: done
tags: [security, app, pi-extension, protocol]
parent: feature-owner-message-e2e-authentication
depends_on: [feature-owner-message-e2e-authentication-schema-handshake-frames]
release_binding: null
gate_origin: null
created: 2026-07-23
updated: 2026-07-23
---

# App secure channel (crypto, persistence, handshake, adapter)

## Brief

Design Units 3, 4-app, 6, 7-app of the parent feature. New `app/lib/data/transport/secure_channel.dart` using the installed `cryptography` 2.9.0 package (no new pub dep); channel key in FlutterSecureStorage + seq counters; `pair_request_flow.dart` ephemeral DH + Owner-signed transcript + generated `PairRequest` DTO (replaces handwritten map) + `pair_ok.dh_sig` verification against QR `epk`; protected PeerChannel adapter wired in the pairing adopt path.

Acceptance: same KAT vector passes (interop proof); forged `pair_ok` aborts pairing with nothing persisted; sealed round-trip; tamper/replay rejection mirrors extension.

Design: see the parent feature body's Implementation Units and Cryptographic
design sections — this story is a checkpoint of that design, not a
standalone spec.

## Implementation notes

- Added the cryptography-backed X25519/HKDF/transcript/XChaCha20-Poly1305 module and reproduced the corrected cross-language KAT byte-for-byte. The protected frame carries `seqLE64` in its authenticated clear header (`0x01 || seq || nonce || ciphertext || tag`), incorporating the implementation-time wire-contract correction.
- Stored directional keys and monotonic send/receive high-water marks in a dedicated per-peer FlutterSecureStorage entry. Peer metadata writes preserve advanced counters, mesh hydration preserves device-local channel state, and partial writes erase the peer/channel pair fail-closed.
- Upgraded pairing to emit generated `PairRequest`, sign the app DH transcript with the existing Owner identity, verify the Pi response against the QR Pi key, and persist nothing on missing/forged DH fields.
- Added `SecurePeerChannel`, including room/control passthrough, durable sequence reservation, plaintext/authentication audit drops, and detach after five consecutive failures. Pairing adoption and reconnect now construct the secure adapter; legacy keyless peers fail closed and require re-pairing.
- Verification: `flutter analyze` passed with no issues. The 799-test unit suite passed with `flutter test --concurrency=1` over all non-e2e test roots. The unfiltered command additionally discovers the separately orchestrated Docker e2e files and fails without their runner-provided endpoints, as expected; those tests are owned by the later e2e story.

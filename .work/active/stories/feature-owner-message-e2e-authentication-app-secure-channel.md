---
id: feature-owner-message-e2e-authentication-app-secure-channel
kind: story
stage: implementing
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

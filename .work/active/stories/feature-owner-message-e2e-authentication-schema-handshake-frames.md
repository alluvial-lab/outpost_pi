---
id: feature-owner-message-e2e-authentication-schema-handshake-frames
kind: story
stage: implementing
tags: [security, app, pi-extension, protocol]
parent: feature-owner-message-e2e-authentication
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-23
updated: 2026-07-23
---

# Schema + codegen for handshake frames

## Brief

Extend `protocol/schema/app-pi-client.schema.json` (`pair_request` + `dh_pk`, `dh_sig`) and `app-pi-server.schema.json` (`pair_ok` + `dh_pk`, `dh_sig`); regenerate TS + Dart DTOs; extend fixtures including the known-answer AEAD/HKDF vector (fixed DH keys, token, seq, plaintext → exact sealed frame bytes).

Acceptance: generated `PairRequest`/`PairOk` carry `dhPk`/`dhSig` in TS + Dart; `protocol/` checks pass; KAT vector committed.

Design: see the parent feature body's Implementation Units and Cryptographic
design sections — this story is a checkpoint of that design, not a
standalone spec.

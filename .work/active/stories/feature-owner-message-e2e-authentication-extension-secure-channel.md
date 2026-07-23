---
id: feature-owner-message-e2e-authentication-extension-secure-channel
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

# Extension secure channel (crypto, persistence, handshake, adapter)

## Brief

Design Units 2, 4-ext, 5, 7-ext of the parent feature. New `pi-extension/src/transport/secure_channel.ts`; add `@noble/curves` + `@noble/ciphers` deps; `PeerRecord` channel-key + seq persistence in `storage.ts` (verify `peers.json` `0600`); `owner_multiplexer.handlePairRequest` dh_sig verification + extended `pair_ok`; `SecurePeerChannel` adapter with plaintext-post-key rejection and 5-failure detach.

Acceptance: KAT vector passes; bad `dh_sig` → `pair_error bad_dh_sig` with no peer record; channel key persisted before `pair_ok` sent; plaintext post-key dropped + audited.

Design: see the parent feature body's Implementation Units and Cryptographic
design sections — this story is a checkpoint of that design, not a
standalone spec.

---
id: feature-owner-message-e2e-authentication-extension-secure-channel
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

# Extension secure channel (crypto, persistence, handshake, adapter)

## Brief

Design Units 2, 4-ext, 5, 7-ext of the parent feature. New `pi-extension/src/transport/secure_channel.ts`; add `@noble/curves` + `@noble/ciphers` deps; `PeerRecord` channel-key + seq persistence in `storage.ts` (verify `peers.json` `0600`); `owner_multiplexer.handlePairRequest` dh_sig verification + extended `pair_ok`; `SecurePeerChannel` adapter with plaintext-post-key rejection and 5-failure detach.

Acceptance: KAT vector passes; bad `dh_sig` → `pair_error bad_dh_sig` with no peer record; channel key persisted before `pair_ok` sent; plaintext post-key dropped + audited.

Design: see the parent feature body's Implementation Units and Cryptographic
design sections — this story is a checkpoint of that design, not a
standalone spec.

## Implementation discovery

The initial KAT carried `seqLE64` only as AEAD associated data, so
`open(key, frame, lastSeq)` could not recover an arbitrary authenticated
sequence or survive a dropped frame. The orchestrator resolved the discovery
in commit `d9b0d15` by correcting the authoritative wire format and KAT to
`0x01 || seqLE64 || nonce24 || ciphertext`, with the clear sequence also bound
as AEAD associated data. The implementation now parses and rejects replay from
that corrected header before AEAD verification and reproduces the regenerated
KAT byte-for-byte.

## Implementation notes

- Added X25519/HKDF transcript and directional-key derivation plus
  XChaCha20-Poly1305 seal/open in `transport/secure_channel.ts`, using the
  corrected authenticated sequence header.
- Persisted Pi-relative `send || recv` key bytes as one 64-byte base64 field and
  uint64 high-waters as decimal strings. Peer mutations are serialized,
  atomically written at mode `0600`, and sequence updates are fenced by the
  expected channel key so a detached pre-re-pair adapter cannot overwrite fresh
  state.
- The owner multiplexer verifies the Owner-signed app DH transcript before
  token consumption, persists derived state before plaintext `pair_ok`, signs
  the Pi transcript, supports signed re-pair, and refuses legacy records without
  channel keys. Async relay ingress is FIFO-serialized so a newly attached
  secure adapter receives the triggering protected reconnect frame.
- `SecurePeerChannel` seals all post-key egress, rejects/audits plaintext,
  tamper, and replay without exposing payloads, persists high-waters, and
  detaches after five consecutive open failures. `PlainPeerChannel` remains
  only for pair and error exchange.
- Verification: `./node_modules/.bin/tsc --noEmit`; full Vitest suite (54 files,
  897 passed, 3 skipped); and `corepack pnpm build` all passed on 2026-07-23.

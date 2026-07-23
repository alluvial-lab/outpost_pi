---
id: feature-owner-message-e2e-authentication-e2e-protected-channel
kind: story
stage: implementing
tags: [security, app, pi-extension, protocol]
parent: feature-owner-message-e2e-authentication
depends_on: [feature-owner-message-e2e-authentication-extension-secure-channel, feature-owner-message-e2e-authentication-app-secure-channel]
release_binding: null
gate_origin: null
created: 2026-07-23
updated: 2026-07-23
---

# E2E cases for the protected owner channel

## Brief

Extend `app/test/e2e/` (driven by `e2e/run-pairing.sh`): (1) pairing establishes a protected channel and sealed round-trip works; (2) forged `ct` injected at the relay is dropped + audited; (3) tampered `dh_sig` → pairing rejected; (4) plaintext post-key frame rejected; (5) sealed channel survives relay reconnect (Toxiproxy) + `session_sync` recovery. Existing pairing e2e cases must pass unmodified against the new handshake.

Acceptance: all five cases green in CI (`e2e-pairing.yml`), existing 7 cases unaffected.

Design: see the parent feature body's Implementation Units and Cryptographic
design sections — this story is a checkpoint of that design, not a
standalone spec.

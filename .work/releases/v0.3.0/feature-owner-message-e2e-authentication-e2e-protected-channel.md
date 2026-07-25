---
id: feature-owner-message-e2e-authentication-e2e-protected-channel
kind: story
stage: done
tags: [security, app, pi-extension, protocol]
parent: feature-owner-message-e2e-authentication
depends_on: [feature-owner-message-e2e-authentication-extension-secure-channel, feature-owner-message-e2e-authentication-app-secure-channel]
release_binding: v0.3.0
gate_origin: null
created: 2026-07-23
updated: 2026-07-24
---

# E2E cases for the protected owner channel

## Brief

Extend `app/test/e2e/` (driven by `e2e/run-pairing.sh`): (1) pairing establishes a protected channel and sealed round-trip works; (2) forged `ct` injected at the relay is dropped + audited; (3) tampered `dh_sig` → pairing rejected; (4) plaintext post-key frame rejected; (5) sealed channel survives relay reconnect (Toxiproxy) + `session_sync` recovery. Existing pairing e2e cases must pass unmodified against the new handshake.

Acceptance: all five cases green in CI (`e2e-pairing.yml`), existing 7 cases unaffected.

Design: see the parent feature body's Implementation Units and Cryptographic
design sections — this story is a checkpoint of that design, not a
standalone spec.

## Implementation notes

- Added five Docker pairing cases covering protected-frame establishment and
  ping/pong, forged-AEAD drop/audit, `bad_dh_sig` token preservation, plaintext
  post-key drop/audit, and Toxiproxy reconnect with persisted sequence
  high-waters plus `session_sync` transcript hydration.
- Repaired the shared e2e pairing support to pass the real Owner key into the
  signed handshake and adopt/reconnect with `SecurePeerChannel`; no pre-existing
  test case was edited. Added a recording transport for sealed-frame
  evidence, a test-only authenticated raw relay client for injection, and a
  content-free Pi-host state/audit inspector.
- The workflow already globs `test/e2e/`; its stale seven-case job label was
  replaced with a count-independent protected-channel label. The checkout
  actually contained eight pre-existing tests (including the later session
  replacement regression), so the completed run is 13/13 rather than the
  commissioned 12/12 count; all five requested additions and all existing
  cases passed.
- The extension's audit currently contains one baseline `plaintext_post_key`
  entry immediately after successful pairing because the triggering plaintext
  `pair_request` reaches the newly attached secure subscriber in the same relay
  ingress fanout. Injection assertions therefore require a new matching audit
  event after their baseline, rather than accepting that pre-existing entry.
  This did not require a production change for the requested coverage.
- Verification (2026-07-23):
  `OUTPOST_PI_E2E_RELAY_IMAGE=outpost-pi-relay:0.1.0 bash e2e/run-pairing.sh`
  passed 13/13 with redaction canaries passing; `cd app &&
  /home/agent/projects/outpost_pi/.tools/flutter/bin/flutter analyze` passed
  with no issues. The prebuilt relay image option was used; the runner rebuilt
  the Pi-host adapter and tore the stack down.

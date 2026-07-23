---
id: feature-owner-message-e2e-authentication-docs-deploy-rollforward
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

# Docs + deploy roll-forward

## Brief

Design Unit 8 of the parent feature. `PROTOCOL.md`: replace the aspirational App-key row with the real design, remove "no E2E" claims for the owner channel, update the relay-operator threat row, keep the relay-metadata-visibility statement. `AGENTS.md`: paired-wire-change entry (app + extension hard cutover, re-pair required, deploy order: extension restart → app sideload). `docs/SPEC.md` data-plane description. Fix the stale `qr.ts` "E2E rollback" comment.

Acceptance: docs pass the gate-docs drift standard (no false/stale assertions); cutover note follows the 0.1.0 paired-wire format.

Design: see the parent feature body's Implementation Units and Cryptographic
design sections — this story is a checkpoint of that design, not a
standalone spec.

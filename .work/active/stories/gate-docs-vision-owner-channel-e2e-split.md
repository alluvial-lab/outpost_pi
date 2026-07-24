---
id: gate-docs-vision-owner-channel-e2e-split
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: docs
created: 2026-07-24
updated: 2026-07-24
---

# VISION still says the owner channel has no E2E protection

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/VISION.md:54-56,83-85`
- Contradicting source: `pi-extension/src/transport/secure_channel.ts:153-186`

## Current doc text
> Not E2E encrypted today. Transport is TLS; the relay sees plaintext envelope contents. Self-hosting is the mitigation; E2E is roadmap-additive.

## Contradiction
The shipped owner channel seals post-pairing JSON with XChaCha20-Poly1305. Only cross-PC Pi↔Pi payloads remain relay-readable.

## Required edit
Replace both assertions with the split trust model: app↔Pi owner payloads are E2E-protected; routing metadata and cross-PC Pi↔Pi envelopes remain visible to the relay. Rolling-foundation: no "previously" prose.

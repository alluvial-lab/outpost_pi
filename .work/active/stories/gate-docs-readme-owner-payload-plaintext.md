---
id: gate-docs-readme-owner-payload-plaintext
kind: story
stage: review
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: docs
created: 2026-07-24
updated: 2026-07-24
---

# Root README still tells users owner payloads are relay-visible plaintext

## Drift category
readme-staleness

## Location
- Doc: `README.md:50-52,73-76`
- Contradicting source: `PROTOCOL.md:461-483`

## Current doc text
> It can see the current plaintext envelope contents; payloads are not end-to-end encrypted in the current version.

## Contradiction
Owner-channel payloads are now sealed end to end. The relay still sees metadata and unprotected cross-PC envelopes.

## Required edit
Replace the blanket plaintext claim with the current owner-channel/cross-PC distinction.

## Implementation notes

Updated the root README to describe sealed app↔Pi owner payloads, visible routing metadata, and relay-readable cross-PC envelopes.

---
id: gate-docs-site-readme-pre-e2e-trust-model
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

# Site README still advertises the pre-E2E trust model

## Drift category
readme-staleness

## Location
- Doc: `site/README.md:3-6`
- Contradicting source: `PROTOCOL.md:451-480`

## Current doc text
> Payloads are not end-to-end encrypted at the application layer in the current MVP.

## Contradiction
App↔Pi owner payloads are now E2E-encrypted and authenticated after pairing.

## Required edit
Replace the statement with the owner-channel E2E/current limitation split.

## Implementation notes

Updated the site README to describe authenticated owner-channel E2E and the relay's metadata and cross-PC visibility limits.

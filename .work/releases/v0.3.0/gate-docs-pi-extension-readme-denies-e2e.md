---
id: gate-docs-pi-extension-readme-denies-e2e
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: docs
created: 2026-07-24
updated: 2026-07-24
---

# Pi-extension README repeatedly denies the shipped owner-channel E2E layer

## Drift category
readme-staleness

## Location
- Doc: `pi-extension/README.md:107-109,156-159,247-255`
- Contradicting source: `pi-extension/src/extension/owner_multiplexer.ts:419-479`

## Current doc text
> The relay sees plaintext envelopes at rest and in forwarding. This is not app-layer E2E encryption; there is no app-layer E2E encryption in the current implementation.

## Contradiction
Pairing now derives and persists directional owner-channel keys, and post-pairing frames are sealed. Inline images are protected by the same owner-channel envelope.

## Required edit
Replace all three stale sections with one consistent owner-channel E2E description and retain the cross-PC/metadata caveats.

## Implementation notes

Replaced the three stale README sections with the shipped sealed owner-channel model, including inline-image protection, metadata visibility, and relay-readable cross-PC caveats.

## Review

Bounded inline review (orchestrator, 2026-07-24): diff inspected against the
item's Required edit and the cited contradicting sources — claims match the
shipped owner-channel E2E contract (sealed ct, metadata/cross-PC caveats
retained, rolling-foundation prose). Approved -> done.

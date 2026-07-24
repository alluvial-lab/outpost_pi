---
id: gate-docs-relay-readme-ct-not-e2e
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

# Relay README says ct is not end-to-end encrypted

## Drift category
readme-staleness

## Location
- Doc: `relay/README.md:44-47`
- Contradicting source: `pi-extension/src/transport/secure_channel.ts:153-186`

## Current doc text
> The payload (ct field) is forwarded as opaque bytes and is not end-to-end encrypted in the current version. A compromised or malicious relay would be able to see the commands you send.

## Contradiction
Post-pairing owner-channel ct contains a versioned XChaCha20-Poly1305 sealed frame. Relay operators cannot read those commands or responses, though they retain metadata visibility and can read cross-PC envelopes.

## Required edit
Describe opaque encrypted owner ct, retain honest metadata/cross-PC limits, and remove the blanket command/response readability claim.

## Implementation notes

Updated relay operator documentation to describe opaque encrypted owner `ct`, visible routing metadata, and readable cross-PC envelopes.

## Review

Bounded inline review (orchestrator, 2026-07-24): diff inspected against the
item's Required edit and the cited contradicting sources — claims match the
shipped owner-channel E2E contract (sealed ct, metadata/cross-PC caveats
retained, rolling-foundation prose). Approved -> done.

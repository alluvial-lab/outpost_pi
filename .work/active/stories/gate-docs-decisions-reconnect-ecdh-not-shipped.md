---
id: gate-docs-decisions-reconnect-ecdh-not-shipped
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

# DECISIONS describes a reconnect-time ECDH design that was not shipped

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/DECISIONS.md:70`
- Contradicting source: `pi-extension/src/extension/owner_multiplexer.ts:419-479`

## Current doc text
> Forward secrecy | ECDH ephemeral per reconnect. Long-lived Curve25519 key only authenticates identity.

## Contradiction
X25519 is ephemeral per pairing, not per reconnect. Directional channel keys are persisted and reused across reconnects; Ed25519 Owner/Pi keys authenticate the pairing transcript; there is no long-lived Curve25519 identity key.

## Required edit
Replace the row with the actual signed ephemeral-X25519-per-pairing and persisted-key reconnect contract.

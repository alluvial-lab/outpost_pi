---
id: gate-docs-relay-claudemd-plaintext-persistence
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.2.0
gate_origin: docs
created: 2026-07-20
updated: 2026-07-20
---

# Relay guidance claims ciphertext-only stateless operation

## Drift category
repo-skill-staleness

## Location
- Doc: `relay/CLAUDE.md:3-4,36-39,46`
- Contradicting source: `docs/DECISIONS.md:80,100-101`

## Current doc text
> [The relay] routes ciphertext ... never decrypts payloads ... only metadata is visible ... the relay is stateless.

## Contradiction
Current trust documentation states that TLS protects transit but the relay sees plaintext payload contents. Current architecture also owns SQLite mesh-membership persistence and ephemeral room/presence state; only message routing has no durable queue.

## Required edit
Rewrite the relay overview and security policy for opaque forwarding of plaintext-at-relay payloads, no payload logging, stateless message routing, and narrow mesh-membership persistence. Do not describe a nonexistent E2E ciphertext boundary.

## Audit
Documentation drift audit ran inline because nested scanner dispatch was prohibited; isolation was reduced.

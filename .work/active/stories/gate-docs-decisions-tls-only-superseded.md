---
id: gate-docs-decisions-tls-only-superseded
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

# DECISIONS retains the superseded "TLS only, no E2E" decision

## Drift category
foundation-doc-assertion

## Location
- Doc: `docs/DECISIONS.md:100-101`
- Contradicting source: `PROTOCOL.md:451-467`

## Current doc text
> No E2E today; TLS only | The relay sees plaintext envelope contents. Self-hosting is the mitigation.

## Contradiction
The accepted and implemented decision is signed ephemeral-DH pairing plus persisted directional keys and sealed owner-channel frames. Self-hosting remains relevant for metadata and cross-PC traffic, not as the sole owner-payload confidentiality mechanism.

## Required edit
Rewrite these decision rows in place around owner-channel E2E, retaining the limits for routing metadata and cross-PC traffic.

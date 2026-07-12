---
id: rebrand-cross-client-auth-contract-test
created: 2026-07-12
updated: 2026-07-12
tags: [rebrand, testing, security, pi-extension, app, relay]
---

# Cross-client auth-domain-prefix contract test

## Context

Found by the deep review of the wire-stable migration feature. The auth
domain prefix `outpost-pi-relay-auth-v1\n` is duplicated as a byte constant
in three languages:
- `app/lib/data/transport/ws_transport.dart:34`
- `pi-extension/src/transport/relay_client.ts:14`
- `relay/src/auth/challenge.rs:107`

The relay has a hard-cutover test proving old-prefix rejection. But the app
tests don't assert the bytes they sign, and the extension test only checks
that the signature is 64 bytes. A future half-rename in either client
remains locally green — only a cross-component test would catch it.

## What's needed

Either:
- A cross-component contract test that verifies each client signs over
  `outpost-pi-relay-auth-v1\n ++ nonce` (a shared test vector), or
- A generated/derived contract so the prefix string lives in one place
  (the schema) and is consumed by all three — the harder but better fix,
  aligned with the generated-contracts principle.

## Severity

Important (not blocking 0.1.0 — the constants currently match — but a
future rename could silently break pairing). The current relay cutover
test catches the relay side; this covers the client side.

## Found by

Deep review of `epic-rebrand-to-outpost-pi-wire-and-install-stable-migration`
(2026-07-12).

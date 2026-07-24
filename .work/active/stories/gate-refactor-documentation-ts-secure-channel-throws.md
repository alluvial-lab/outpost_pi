---
id: gate-refactor-documentation-ts-secure-channel-throws
kind: story
stage: implementing
tags: [refactor]
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-24
---

# TypeScript owner-channel helpers omit @throws contracts

## Library
documentation

## Rule
error-path

## Confidence
High

## Location
`pi-extension/src/transport/secure_channel.ts:66`

## Issue
Exported key-derivation, transcript, and sealing helpers throw on malformed lengths, sequences, or nonce sources without documenting those error conditions.

## Fix
Add focused @throws clauses to x25519Shared, deriveDirectionalKeys, pairMacMessage, seal, and other explicitly throwing exports.

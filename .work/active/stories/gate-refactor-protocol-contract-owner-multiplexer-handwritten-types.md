---
id: gate-refactor-protocol-contract-owner-multiplexer-handwritten-types
kind: story
stage: review
tags: []
parent: null
depends_on: []
release_binding: v0.3.0
gate_origin: refactor
created: 2026-07-24
updated: 2026-07-24
---

# Pairing multiplexer handwrites generated app/Pi message types

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
High

## Location
`pi-extension/src/extension/owner_multiplexer.ts:360`

## Issue
The pairing and detach paths handwrite pair_error, pair_ok, and bye, duplicating values in SERVER_MESSAGE_TYPES.

## Fix
Generate a keyed discriminator registry from the schema and use its pair_error, pair_ok, and bye entries when constructing messages.

## Implementation notes

- Added schema-derived client and server keyed discriminator registries to the
  TypeScript protocol generator and regenerated the extension protocol output.
- Updated pairing error/success and detach messages to use
  `SERVER_MESSAGE_DISCRIMINATORS` rather than handwritten discriminators.
- Verification: `cd pi-extension && node --import tsx ../tools/protocol-codegen/src/index.test.ts` (6 passing); `./node_modules/.bin/vitest run src/extension/owner_multiplexer.test.ts` (27 passing); regenerated with `node --import tsx ../tools/protocol-codegen/src/index.ts --target ts --out src/protocol/generated/protocol.generated.ts`.

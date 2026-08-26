---
id: gate-refactor-protocol-contract-owner-multiplexer-pair-discriminator
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: v0.9.0
gate_origin: refactor
created: 2026-08-26
updated: 2026-08-26
---

# Owner multiplexer re-enumerates the generated pair-request discriminator

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
High

## Relevance
Release-relevant

## Location
`pi-extension/src/extension/owner_multiplexer.ts:176,309`

## Issue
The pair-request guard compares `message.type` and `inner.type` to the handwritten `"pair_request"` literal even though the generated client-message registry already defines that discriminator.

## Fix
Add or consume a generated named client-message discriminator for `pair_request` and use it for both runtime checks (and derive the related narrowing type from the same generated source).

## Closure

- Verified the pre-change handwritten comparisons at `owner_multiplexer.ts:176,309`.
- The TypeScript generator now emits `CLIENT_MESSAGE_DISCRIMINATORS` from the app/Pi client schema. `owner_multiplexer.ts` uses `CLIENT_MESSAGE_DISCRIMINATORS.pair_request` at the runtime checks now at `:178,311`, and `PairRequestMessage` derives its narrowing type from `typeof CLIENT_MESSAGE_DISCRIMINATORS.pair_request`.
- Behavior is unchanged: only the discriminator source and type expression moved to the generated seam.
- Verification: focused `owner_multiplexer.test.ts` — 30 passed; protocol codegen checks — 7 passed; `corepack pnpm typecheck` — passed; `corepack pnpm test` — 60 files, 1103 passed, 3 skipped (1106 tests); `corepack pnpm build` — passed.

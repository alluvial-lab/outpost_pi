---
id: gate-refactor-protocol-contract-owner-multiplexer-compaction-discriminator
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

# Owner multiplexer re-enumerates the generated compaction discriminator

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
High

## Relevance
Release-relevant

## Location
`pi-extension/src/extension/owner_multiplexer.ts:706,740`

## Issue
The offline compaction arbitration checks handwritten `"compaction"` type literals instead of consuming the generated `SERVER_MESSAGE_DISCRIMINATORS.compaction` value.

## Fix
Replace both comparisons with the generated server-message discriminator (or a derived helper) so schema renames cannot leave the offline-buffer and replay-arbitration paths out of sync.

## Closure

- Verified the pre-change handwritten comparisons at `owner_multiplexer.ts:706,740`.
- Both offline compaction paths now derive the discriminator from `SERVER_MESSAGE_DISCRIMINATORS.compaction`, at the updated anchors `owner_multiplexer.ts:708,742`.
- Behavior is unchanged: offline-buffer tracking and session-history arbitration retain the same compaction matching and suppression semantics while consuming the generated server contract.
- Verification: focused `owner_multiplexer.test.ts` — 30 passed; `corepack pnpm typecheck` — passed; `corepack pnpm test` — 60 files, 1103 passed, 3 skipped (1106 tests); `corepack pnpm build` — passed.

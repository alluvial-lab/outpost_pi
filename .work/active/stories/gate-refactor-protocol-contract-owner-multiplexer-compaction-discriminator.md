---
id: gate-refactor-protocol-contract-owner-multiplexer-compaction-discriminator
kind: story
stage: implementing
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

---
id: gate-refactor-documentation-transcript-log-contracts
kind: story
stage: implementing
tags: [refactor]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: refactor
created: 2026-08-25
updated: 2026-08-25
---

# Document TranscriptEventLog public service contracts

## Library
documentation

## Rule
service-contract

## Confidence
High

## Location
`pi-extension/src/session/transcript_event_log.ts:37`

## Issue
The exported aggregate's public methods are undocumented, including `record()` whose discriminated result distinguishes recorded, duplicate, unavailable, and failed durability outcomes.

## Impact
Consumers must infer persistence-before-visibility, hydration, replacement, identity lookup, and failure behavior from implementation details.

## Fix
Add intent-bearing JSDoc to the public methods, with explicit outcome semantics for `record()` and lifecycle ownership for persistence binding/unbinding; avoid signature restatement.

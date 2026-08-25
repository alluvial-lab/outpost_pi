---
id: gate-refactor-documentation-durable-encoder-throws
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

# Document the durable transcript encoder failure contract

## Library
documentation

## Rule
error-path

## Confidence
High

## Location
`pi-extension/src/session/durable_transcript_event.ts:22`

## Issue
The exported encoder throws for an invalid or non-JSON-safe canonical event, but its JSDoc has no `@throws` contract.

## Impact
Callers cannot tell from the public API that validation failure is synchronous and must be handled before persistence or visibility.

## Fix
Add a meaningful `@throws` clause describing the rejected event conditions and boundary semantics without restating the parameter type.

---
id: gate-refactor-documentation-sdk-transcript-contracts
kind: story
stage: done
tags: [refactor]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: refactor
created: 2026-08-25
updated: 2026-08-25
---

# Document the SDK projection's durable transcript API

## Library
documentation

## Rule
service-contract

## Confidence
High

## Location
`pi-extension/src/session/sdk_session_projection.ts:432`

## Issue
The new public `recordDurableTranscriptEvent()` and `recordedTranscriptTs()` service methods have no JSDoc, even though the first returns a four-way durability result and the second carries canonical timestamp ownership.

## Impact
Composition-root callers can misinterpret `duplicate` versus failure or substitute a producer timestamp without understanding when durable authority exists.

## Fix
Document persistence-before-visibility, each result status, identity scope, and the meaning of an absent recorded timestamp.

## Implementation
- Added service-contract JSDoc for durability outcomes and session/event timestamp identity in `pi-extension/src/session/sdk_session_projection.ts`.

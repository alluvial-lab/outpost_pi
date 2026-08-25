---
id: gate-refactor-documentation-session-history-throws
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

# Document session-history replay precondition failures

## Library
documentation

## Rule
error-path

## Confidence
High

## Location
`app/lib/data/sync/session_history_replay.dart:20`

## Issue
Both public replay mappers reject an empty canonical session ID with `ArgumentError`, but their dartdoc states only a requirement and never declares the thrown error.

## Impact
Callers can treat replay as total and fail to route an identity-boundary violation through the app's persistence-degradation path.

## Fix
Add explicit `Throws [ArgumentError]` contract notes to both public replay functions and state the canonical-session precondition once without restating their signatures.

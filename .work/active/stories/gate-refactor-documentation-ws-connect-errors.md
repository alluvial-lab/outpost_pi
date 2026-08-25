---
id: gate-refactor-documentation-ws-connect-errors
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

# Document WebSocket connect failure and cancellation outcomes

## Library
documentation

## Rule
error-path

## Confidence
High

## Location
`app/lib/data/transport/ws_transport.dart:108`

## Issue
The public `WsTransport.connect()` factory documents readiness and cancellation effects but not the errors it throws for cancellation, malformed relay challenge/readiness frames, authentication/socket failure, or cleanup failure.

## Impact
Connection owners cannot derive which failures are retryable or what teardown has completed from the factory contract alone.

## Fix
Add dartdoc error-contract notes for cancellation and boundary failures, including the resource-ownership guarantee once lifecycle teardown is corrected.

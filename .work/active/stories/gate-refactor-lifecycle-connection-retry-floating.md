---
kind: story
release_binding: null
parent: feature-app-async-lifecycle-ownership
stage: done
id: gate-refactor-lifecycle-connection-retry-floating
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-17
---

# Connection retry timer discards the reconnect future

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`app/lib/data/transport/connection_manager.dart:1190`

## Issue
The retry `Timer` callback calls async `_connect(peer)` without awaiting, returning, `unawaited(...)`, or attaching a catch, so reconnect ordering and unexpected errors are not explicitly owned by the timer lifecycle.

## Fix
Make the fire-and-forget intent explicit with `unawaited(_connect(peer).catchError(...))`, or route retries through an awaited/serialized reconnect loop that owns cancellation and error reporting.

## Implementation

Closed by `feature-app-async-lifecycle-ownership-connection-persistence`: the
retry timer validates manager/peer lifecycle and delegates to an owned awaited
boundary; expected failures keep existing retry state, while unexpected escapes
emit typed diagnostics for watchdog recovery.

---
kind: story
release_binding: null
parent: feature-app-async-lifecycle-ownership
stage: done
id: gate-refactor-lifecycle-sync-service-floating-rebinds
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-17
---

# SyncService drops lifecycle-sensitive async rebind futures

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`app/lib/data/sync/sync_service.dart:305,488,521,722,727`

## Issue
Several session lifecycle operations are launched behind `// ignore: discarded_futures` without explicit `unawaited(...).catchError(...)`: pending-send failure materialization, online activation, room/session rebind, connection switch, and history replay.

## Fix
Separate truly background operations from ordering-critical rebinds; await/serialize the latter and wrap intentional fire-and-forget calls in `unawaited(...).catchError(...)` with logging and stale-session guards.

## Implementation

Closed by `feature-app-async-lifecycle-ownership-sync-failure-semantics`:
status/room lifecycle work is serialized as activation, stale-ref check,
held-message resend, then sync; disposal/session rotation guards every async
gap. Controlled stale-read/send and new-session sync tests pass.

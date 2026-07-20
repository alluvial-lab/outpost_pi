---
kind: story
release_binding: v0.2.0
parent: feature-app-async-lifecycle-ownership
stage: done
id: gate-refactor-lifecycle-room-persist-fire-and-forget
tags: []
depends_on: []
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-20
---

# Room persistence writes are fire-and-forget without error handling

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
app/lib/data/transport/connection_manager.dart:661

## Issue
_persistRoomsForPeer(key) is called from control-frame handling with only a lint ignore; similar calls at 732, 782, 923, 935, 971. Storage failures dropped, writes can outlive teardown.

## Fix
needs analysis

## Implementation

Closed by `feature-app-async-lifecycle-ownership-connection-persistence`: all
six room-cache mutation sites now feed one latest-wins drain per peer with
staleness/disposal guards and typed failure diagnostics. Controlled storage
ordering tests and analysis pass.

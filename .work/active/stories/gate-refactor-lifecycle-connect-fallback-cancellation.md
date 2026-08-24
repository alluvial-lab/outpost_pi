---
id: gate-refactor-lifecycle-connect-fallback-cancellation
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: refactor
created: 2026-08-24
updated: 2026-08-24
---

# Complete a superseded reconnect hedge even when its factories remain pending

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Location
`app/lib/data/transport/connection_manager.dart:722`

## Issue
`_connectWithFreshFallback` has no cancellation settlement path: after `_invalidateConnectSupervisor` cancels `ownerToken`, the fallback callback returns without completing `winner`, so an indefinitely pending primary leaves `_connectInFlight` pending forever and every later peer/room connection waits behind it.

## Fix
Make owner cancellation cancel every attempt and settle the hedge future immediately, while retaining late-result cleanup so any channel returned by a non-cancellable factory is closed exactly once.

---
id: gate-refactor-lifecycle-hedge-cancel-teardown
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: refactor
created: 2026-08-25
updated: 2026-08-25
---

# Make hedge cancellation teardown total under cleanup failures

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Location
`app/lib/data/transport/ws_transport.dart:350`

## Issue
The cancellation and connect-failure paths await `sub.cancel()` before `ws.sink.close()`, so a subscription-cancel error skips socket closure; the resulting rejected cancellation future also escapes the hedge's loser wait at `connection_manager.dart:850`, leaving the winner uncompleted.

## Impact
A losing same-device socket can remain authenticated, later supersede the intended winner, and strand `ConnectionManager` in its connect attempt.

## Fix
Make subscription and socket teardown independently total (settle both even if either fails), normalize cleanup failures after every owned resource has closed, and ensure loser-cleanup failure cannot prevent winner adoption or terminal error completion.

## Implementation

- WebSocket connect cancellation, connect failure, and live transport closure now settle every owned cleanup action before reporting the first cleanup failure, so subscription cancellation cannot skip socket/control-stream closure.
- Reconnect hedge cancellation contains and records loser cleanup failures before continuing fallback startup or winner adoption.
- Regression coverage injects both a failing subscription cleanup followed by socket closure and a failing primary hedge cancellation followed by successful fallback adoption.
- Verified with `flutter test test/data/transport/ws_transport_queue_test.dart test/transport/connection_manager_test.dart --concurrency=2`.

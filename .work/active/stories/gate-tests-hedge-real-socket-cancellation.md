---
id: gate-tests-hedge-real-socket-cancellation
kind: story
stage: implementing
tags: [testing, app, bug]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: tests
created: 2026-08-25
updated: 2026-08-25
---

# Prove reconnect hedge loser cancellation at the real WebSocket boundary

## Priority
High

## Value evidence
Item: `story-fix-app-reconnect-hedge-auth-boundary-and-post-adoption-cancel`.
The root cause says a fallback already in flight could authenticate after the
winner was adopted and supersede the live same-device socket. The named
regression `authenticated primary cancels fallback before a second relay auth`
completes the primary before the 120 ms fallback timer, then only asserts the
auth count remains one (`app/test/transport/connection_manager_test.dart:659-708`): no fallback socket is ever in flight, so the test is weaker than the
root-cause claim. The auth-stall test uses `WsTransport`, but its loopback relay
only counts auth frames and does not assert that the cancelled socket reached
EOF before the competing auth (`:609-655`, fake relay `:1534-1590`).

## Gap type
bug-regression / real transport cancellation seam

## Suggested test
```dart
// Drive ConnectionManager + production WsTransport against a loopback relay
// that records hello/auth/socket-close ordering and enforces real
// same-device supersession semantics. Hold readiness so the fallback timer
// fires and a losing socket exists, release the winner at the adoption race,
// then assert loser EOF/close completes before winner publication and that no
// later auth can supersede StatusOnline. Cover cancellation both before and
// after WsTransport's handedOff boundary with explicit completers.
```

## Test location (suggested)
`app/test/transport/connection_manager_test.dart`

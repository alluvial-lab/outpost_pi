---
id: gate-tests-hedge-real-socket-cancellation
kind: story
stage: done
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

## Implementation

Added a real-loopback `ConnectionManager` + production `WsTransport` boundary
test. The relay fake now services sockets continuously while auth readiness is
held, records each auth and peer-observed EOF, and can release attempts
independently. The test stalls the primary through auth, lets the hedge timer
fire, and proves the exact wire order:

```text
auth primary → primary EOF → auth fallback → StatusOnline
```

It then releases the cancelled primary handler and proves there is still only
one online publication and no third/later authentication that can supersede
the adopted channel. This is stronger than the old timer-only test: a real
losing socket exists, reaches server-observed EOF, and only then may the
fallback authenticate and publish. The adjacent controllable-channel tests
continue to cover cancellation after the factory/handed-off boundary and
disposal of late-finishing channels.

No product defect was found. Early red runs revealed that the original fake's
`StreamIterator` intentionally stopped reading while auth was held, so it could
not observe peer EOF; the fake was corrected to a continuously serviced socket
state machine rather than weakening the assertion.

Verification:

- `flutter test test/transport/connection_manager_test.dart --name 'real socket loser|auth-read stall' --concurrency=2` (2 passed)
- `flutter test test/transport/connection_manager_test.dart --plain-name 'real socket loser reaches EOF before winner publishes online' --concurrency=2` (passed)

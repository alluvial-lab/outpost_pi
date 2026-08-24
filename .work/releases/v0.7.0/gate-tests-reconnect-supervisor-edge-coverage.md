---
id: gate-tests-reconnect-supervisor-edge-coverage
kind: story
stage: done
tags: [testing, app]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: tests
created: 2026-08-24
updated: 2026-08-25
---

# Prove reconnect supersession closes every losing authenticated channel

## Priority
High

## Value evidence
Items: `story-fix-app-connect-supervisor-duplicate-auth-cycle` and
`story-fix-app-reconnect-stale-first-attempt`. Their production contract is one
live/authenticating socket per `(peer, room)`, with every superseded or hedged
loser closed before it can recreate the relay's same-device duplicate-auth
cycle. The same-target regression proves one factory call
(`app/test/transport/connection_manager_test.dart:150-177`), while the hedge
regression only proves that `latePrimary` is not adopted
(`app/test/transport/connection_manager_test.dart:489-546`). It never observes
`close()`, and no deterministic case switches peer/room or disposes while a
connect/hedge is in flight. This is weaker than the fixes' root-cause and loser
ownership claims.

## Gap type
bug-regression / async state-transition matrix

## Suggested test
```dart
// Use explicit factory-start/release barriers and close-counting channels.
// 1. A different peer/room request arrives while A is blocked: B's factory
//    must not start until A returns and its channel has closed exactly once.
// 2. The reconnect fallback starts, then the primary returns late: the late
//    primary closes exactly once and only the fallback reaches StatusOnline.
// 3. dispose/disconnect while primary and fallback are pending: every eventual
//    channel closes, with no later Online or retry transition.
```

## Test location (suggested)
`app/test/transport/connection_manager_test.dart`

## Implementation
Added close-counting, barrier-driven regressions for target supersession,
late-primary fallback loss, and disposal while both reconnect attempts remain
pending. The tests assert each losing channel closes exactly once and that no
post-disposal attempt can publish `StatusOnline`.

Evidence: **pins-contract** — all new cases pass against the existing reconnect
supervisor behavior while directly observing the previously unasserted close
boundary.

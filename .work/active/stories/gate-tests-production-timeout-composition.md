---
id: gate-tests-production-timeout-composition
kind: story
stage: done
tags: [testing]
parent: null
depends_on: []
release_binding: v0.12.1
gate_origin: tests
created: 2026-10-04
updated: 2026-10-04
---

# Production timeout composition defeats the handshake-stall classification

## Priority
Critical (release-blocking)

## Value evidence
Item: `story-fix-post-strike-recovery-ladder`
Contract: zero-inbound handshake stalls retry at fixed 1s without escalating.
In production the contract is currently defeated: `WsTransport` classifies
after its default 12s deadline, but `ProductionConnectionFactory` wraps the
whole candidate in a 10s `.timeout` (`production_connection_factory.dart:93–142`),
whose `TimeoutException` becomes `ReachabilityFailureKind.transport` and
feeds the ordinary ladder. New tests bypass the production seam (direct
transport calls with 300ms deadlines; adapter tests inject the kind).
Flagged independently by the security and refactor scanners as the same
seam.

## Gap type
e2e-seam / bug-regression

## Fix
1. `defaultAuthHandshakeTimeout` 12s → 9s so it fires before the production
   candidate timeout (and, with the 3s fallback head start, before the
   manager's 15s whole-attempt deadline).
2. Hoist the interlocking timeouts to named consts
   (`productionWsConnectTimeout`, `kReconnectFallbackDelay`,
   `kConnectAttemptDeadline`) and pin the full ordering —
   `auth < candidate`, `fallback + auth < attempt` — in a seam test so no
   constant can drift alone.

## Test location
`app/test/config/production_connection_factory_test.dart`

## Fixed (2026-10-04)
`defaultAuthHandshakeTimeout` 12s→9s; interlocking timeouts hoisted to named
consts (`productionWsConnectTimeout`, `kReconnectFallbackDelay`,
`kConnectAttemptDeadline`); seam test pins the full ordering (auth <
candidate; fallback+auth < attempt deadline). Join regression strengthened in
the same pass (`gate-tests-join-adoption-room-binding`): _RecordingChannel
adoption, single StatusOnline, room re-bind to the churned room, no retry,
deterministic `pumpEventQueue` drain. `flutter analyze` clean; 28 tests
green across the two files.

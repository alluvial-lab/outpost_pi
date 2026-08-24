---
id: story-fix-app-reconnect-stale-first-attempt
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# First reconnect attempt after a drop stalls the full 10s; immediate retry succeeds in <1s

## Symptom
Capture f32-11f1-92e5 (2026-08-23 20:07-20:41Z): 13 retryConnect/TimeoutException.
Pattern (e.g. 20:40:15-20:40:29, 20:36:16-20:37:37): drop -> connecting ->
TimeoutException at ~11s -> retry -> ONLINE in <1s. Offline windows reach
60-81s while every eventual retry connects instantly. Relay healthy
throughout; connects that succeed take <1s on the same network.

## Root cause
The production factory already constructs a new `WsTransport`,
`IOWebSocketChannel`, and `SecurePeerChannel` for every call; it does not reuse
the prior transport or a manager-owned socket pool. The gap was instead in the
post-`channelDone` recovery policy: `ConnectionManager` serialized exactly one
fresh factory attempt behind the factory's 10-second authentication deadline,
even though the platform socket can still be unwinding at that edge. A first
attempt caught in that teardown/network path therefore blocked all recovery;
only the next backoff attempt got a second independently-created socket.

## Fix approach
Fail-fast + race: either (a) ensure attempt #1 builds a completely fresh
connection (no reuse), or (b) start a parallel second attempt at ~3s and
adopt whichever completes first (happy-eyeballs style). Do NOT lower the
10s deadline globally (slow networks legitimately need it); attack the
stale-reuse, not the timeout.

## Regression test
Unit with injected factory: attempt sequence after channelDone — assert
either attempt #1 is fully fresh (no shared transport/pool objects) or the
racing fallback brings online within ~3-4s simulated; fails-before.

## Verification notes
Live soak churn cluster recovery times should drop (churn oracle unchanged
— clusters are counted from connChannelLost, recovery speed is the win).

## Implementation notes
- **Execution capability:** Sol/high, selected for the async lifecycle race and
  winner/loser resource-ownership review.
- **Files changed:** `app/lib/data/transport/connection_manager.dart`,
  `app/test/transport/connection_manager_test.dart`.
- **Regression test:** `channelDone reconnect races a fresh fallback when the
  first attempt stalls` injects an indefinitely-stalled first reconnect and a
  fresh succeeding fallback. Fails-before evidence: the test did not compile
  because `reconnectFallbackDelay` and the fallback path did not exist. It now
  proves the manager reaches `StatusOnline` through the second fresh factory
  call without changing the production 10-second factory deadline.
- **Confirmation:** targeted regression passed; complete connection-manager
  suite passed (46 tests); `flutter analyze` reported no issues; full
  `flutter test --exclude-tags e2e --concurrency=2` passed (911 tests). The
  original field-only timing signature requires a device soak and is deferred
  to the orchestrator.
- **Bounded inline review:** PASS. The hedge is limited to the first reconnect
  after `channelDone`, preserves single-flight at the public manager boundary,
  closes a late loser, makes the newer same-device fallback authoritative once
  its authentication starts (so it cannot kick an adopted late primary),
  clears its latch on lifecycle invalidation, and leaves ordinary/initial
  connects and the global deadline unchanged.
- **Adjacent issues parked:** none.

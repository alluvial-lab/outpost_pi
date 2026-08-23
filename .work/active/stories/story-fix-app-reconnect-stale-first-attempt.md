---
id: story-fix-app-reconnect-stale-first-attempt
kind: story
stage: implementing
tags: [app, bug]
parent: null
depends_on: []
release_binding: null
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

## Root cause (hypothesis to confirm)
The first reconnect attempt after channelDone reuses something stale
(half-open socket in a pool, cached route/DNS binding, or the old
channel's teardown racing the new connect) — it cannot succeed but takes
the full deadline to fail; the fresh attempt after the timeout succeeds
immediately. Inspect ConnectionManager reconnect path (connection_manager.dart)
+ WebSocket factory: what differs between attempt #1 post-drop and attempt #2?

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

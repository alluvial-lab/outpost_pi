---
id: story-fix-app-connect-supervisor-duplicate-auth-cycle
kind: story
stage: done
tags: [app, relay, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# Connect supervisor races itself: same-device duplicate auth cycles every 2-11s

## Symptom

Operator report (2026-08-23): "random reconnect cycles" on mobile.
Capture `debug/ef5-…c9cc1cea9d20.bin`: 25 `connChannelLost` (all cause
`channelDone`), 14 `retryConnect/TimeoutException`, 5 anomalous clusters.
Relay log `/data/logs/relay.log.2026-08-23` (correlated timestamps
13:13:00–13:22:00, also 12:49–12:58): repeated
`duplicate auth from same device; closed prior conn(s)` — the app opened a
NEW authenticated socket while its prior socket was still established on
the relay, every 2–11 seconds (13:16:08→:10→:14→:15→:26→:27). Phone addr
192.168.40.23 → relay (cross-subnet WiFi path).

## Root cause

`ConnectionManager._connect` cancelled the preceding attempt's token but
immediately called the connection factory again. The production factory can
only observe cancellation before or after `WsTransport.connect`; therefore two
same-`(peer, room)` calls could both open and authenticate sockets before the
first returned and closed itself. The relay then superseded the earlier socket,
and its `channelDone` fed another retry into the same cycle.

## Fix approach

Single-flight connection ownership: one connect attempt per (peer, room)
at a time; late arrivals await or adopt the in-flight connection instead
of opening a second socket. The auth deadline must cancel/supersede the
PRIOR attempt locally before authenticating the new one (it currently
leaves the relay to do the superseding via duplicate-auth).

## Regression test

Unit with injected clock/transport: trigger reconnect while a connect is
in flight → exactly one authenticated socket (assert single auth frame,
no second socket open). Fails-before evidence required. Live: churn
cluster count in a soak slice stays 0 outside scheduled faults (already
enforced by the soak's churn oracle).

## Verification notes

- Relay evidence lines: `13:14:26.993 duplicate auth … closed=1`,
  `13:16:08.759`, `13:16:10.092`, `13:16:14.172`, `13:16:15.749`,
  `13:16:26.383`, `13:16:27.696`.
- Environmental note: phone on 192.168.40.x (different subnet from VM's
  192.168.50.x) — real WiFi drops may seed the first reconnect, but the
  2s-cadence chains are app-induced superseding, not environment.

## Implementation notes

- **Execution capability:** `sol/high`; the defect is a lifecycle-ordering race
  in one service, requiring deterministic interleaving coverage but no broader
  feature coordination.
- **Files changed:** `app/lib/data/transport/connection_manager.dart`,
  `app/test/transport/connection_manager_test.dart`.
- **Fix:** one in-flight Future now owns each `(peer, room)` connect. A same-key
  caller shares it; a different owner cancels and awaits its predecessor, and
  an already-live matching channel is adopted rather than re-authenticated.
  Teardown, adoption, and disposal invalidate queued attempts.
- **Regression test:** `concurrent connect requests for the same peer and room
  share one attempt` uses explicit factory start/release barriers. Fails before
  with `Expected: <1>, Actual: <2>`; passes after with one factory/auth path.
- **Four-step confirmation:** targeted test passes; the complete connection
  manager test file passes (45 tests); `flutter analyze` passes; full
  `flutter test --exclude-tags e2e --concurrency=2` passes (888 tests). The
  relay capture's duplicate-auth chain requires overlapping authenticated
  sockets from one device; sharing the in-flight attempt removes that source,
  while supersession waits for local predecessor closure before new auth.
- **Adjacent issues parked:** none.

## Bounded inline review

**Verdict: pass.** The diff is confined to connection lifecycle ownership, the
barrier test exercises the reported overlap rather than elapsed timing, and
cancellation/teardown paths invalidate queued work. No protocol or persistence
contract changed.

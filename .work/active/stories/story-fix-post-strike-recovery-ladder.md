---
id: story-fix-post-strike-recovery-ladder
kind: story
stage: implementing
tags: [app, bug, lifecycle]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-10-04
updated: 2026-10-04
---

# Post-strike recovery ladder: join in-flight connects, fast-cycle handshake stalls

## Brief

Folded from `backlog-app-connect-cancel-race` plus the recovery half of
verdict #9 (see `story-fix-connection-metronome-death`, 2026-10-04 capture).
After a phone-netstack strike, the app burns minutes recovering for two
app-side reasons, both field-proven:

1. **Cancel race** (backlog item, 2026-09-08 capture: 3 of 4 retry attempts
   cancelled before reaching the wire): a re-entrant `_connect()` /
   connect-deadline supervisor invalidation with a diverged target cancels
   the in-flight attempt; each `_CancelledError` consumes a retry slot and
   re-escalates the ladder. Verdict #9: 8× `retryConnect _CancelledError`
   per episode.
2. **Handshake-stall escalation** (verdict #9 new): during the post-strike
   wedge the phone's OUTBOUND works (`hello` reaches the relay — relay logs
   `handshake step failed phase="auth"` ~11s later) but INBOUND is dead
   (zero `wsIn` rows for those connections); the app gives up ~3s after
   hello and the failure escalates the shared 1→2→5→10→30s ladder
   (`reachabilityBackoffForAttempt`), because backoff only resets on real
   inbound (`onAppFrameObserved`) — exactly what the wedge starves. Net:
   ~4 min offline after one strike, mostly spent in backoff that cannot
   help (the path recovers on phone-side timing, not ours).

The app cannot shorten the wedge itself; it CAN stop multiplying it —
reconnect should land on the first un-wedged socket instead of sleeping
through 30s backoffs mid-episode.

## Design

**Unit 1 — same-peer re-entrant connects join the in-flight attempt.**
In `ConnectionManager._connect` / `_connectWithFreshFallback`
(`app/lib/data/transport/connection_manager.dart`): when a connect is
requested for the same peer while a supervisor-owned attempt for that peer
is alive and within its deadline, the re-entrant caller awaits/adopts the
existing attempt instead of cancelling it. Diverged-target invalidation
(peer actually changed, explicit teardown, dispose) still cancels — that
behavior is correct and must be preserved. Pin the canceller identity with
a targeted test before changing semantics (the backlog's "cancellation-site
logging" need becomes an assertion on join-instead-of-cancel).

**Unit 2 — handshake-stall is a fast-cycle failure class, not ladder fuel.**
Locate the give-up path for "transport open, hello sent, no preauth
reply ~3s" (challengeCompleter / connect-attempt deadline interaction in
`ws_transport.dart` + `_connectAttemptDeadline` supervision). Classify it as
a distinct `ReachabilityFailureKind` (e.g. `handshakeStall`); in
`ReachabilityAdapter`, a failure streak of ONLY handshakeStall keeps the
retry delay short and non-escalating (1s fixed; cap e.g. 2s) while any other
failure kind re-enters the normal ladder. Escalation state for other kinds
is preserved across interleaved stalls. Rationale: the stall means "path
wedged" — cheap immediate re-socketing is the fastest way to find the first
healthy path; real network-down failures still back off.

Both units keep existing invariants: one adopted channel per peer, stale
channel-loss events ignored, backoff reset only on real inbound.

## Acceptance

- State-machine tests (fake clock) in `connection_manager` /
  `reachability_adapter` tests:
  - same-peer re-entrant connect during in-flight attempt joins it — no
    cancel of the in-flight attempt, no extra factory call, no retry slot
    burned; diverged-peer invalidation still cancels;
  - handshake-stall failure streak schedules 1s (capped) retries with no
    escalation to 2/5/10/30s; a transport/network failure after stalls
    escalates from the correct rung; real inbound resets everything.
- `flutter analyze` + `flutter test --exclude-tags e2e` green.
- Operator field validation (folds into v0.12.1 UAT): post-strike recovery
  completes in seconds-to-wedge-duration, captures show no
  `retryConnect _CancelledError` chains.

## Verification evidence

(accumulates during implementation)

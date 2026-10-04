---
id: story-fix-post-strike-recovery-ladder
kind: story
stage: review
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

Implemented 2026-10-04 over `3af572be7`:

- **Unit 1 (join)**: `_connect` now joins any in-flight connect whose PEER
  matches, not just the exact `(peerEpk, roomId)` tuple — the room component
  churns during post-strike retargets while `_performConnect`'s same-peer
  branch retains the live room and `_propagateActiveRoom` re-points the
  adopted channel. Diverged-PEER invalidation unchanged. The 3s
  `reconnectFallbackDelay` hedge remains (it hedges, but hedge-loser closes
  don't route failures or burn ladder rungs).
- **Unit 2 (fast-cycle)**: `WsTransport` now owns a pre-auth handshake
  deadline (`defaultAuthHandshakeTimeout` 12s — ahead of the manager's 15s
  backstop, injectable for tests) so the zero-inbound classification
  survives instead of being raced away by the manager timeout. Pre-auth
  failures on sockets that never received a single relay frame classify as
  the new `ReachabilityFailureKind.handshakeStall`; `ReachabilityAdapter`
  holds retries at a fixed 1s (`reachabilityHandshakeStallRetryDelay`) with
  the ladder rung frozen during stall-only streaks; the first non-stall
  failure resumes the frozen rung; real inbound resets everything.
- Tests (all green-first against the fix): manager join ×2 (same-peer room
  churn joins — factory called once, token not cancelled; different peer
  still replaces), adapter stall ladder (freeze at rung 2, 1s through a
  5-stall streak, transport resumes at 5s, inbound resets), transport ×3
  (clean pre-auth close → stall; silent relay + deadline → stall with
  'auth handshake timed out'; challenge-then-silence deadline → frames-seen
  kind preserved as relayRejected).
- `flutter analyze` clean; full suite `flutter test --exclude-tags e2e
  --concurrency=2`: **1,072 passed**.
- Expected field effect (for v0.12.1 UAT): strikes still occur (netstack
  owns them) but captures report `streamError`/`dartProtocolError` honestly
  (story A), no `retryConnect _CancelledError` chains, and post-strike
  recovery cycles ~1s instead of climbing 1→30s over ~4 min.

## Implementation notes

- Execution capability: inline implement (same owner as verdict #9 evidence
  chain; app transport is one cohesive surface).
- Review weight: standard — bounded inline pass (standalone story).
- Files changed: `app/lib/domain/value_objects/reachability.dart`,
  `app/lib/data/transport/reachability_adapter.dart`,
  `app/lib/data/transport/ws_transport.dart`,
  `app/lib/data/transport/connection_manager.dart`, plus the three test
  files (`ws_transport_close_diagnostics_test.dart`,
  `reachability_adapter_test.dart`, `connection_manager_test.dart`).
- Design decisions: factory-owned handshake deadline over manager-timeout
  re-routing (classification knowledge lives where the frames are counted;
  avoids `_ConnectSuperseded` cause-tunnelling through the hedge race);
  `handshakeStall` kept app-local (the reachability schema owns
  states/backoff/heartbeat only — no cross-language failure-kind consumers).
- Discrepancies from design: the give-up path turned out to be the 3s
  fallback hedge plus the 15s manager deadline, not a dedicated preauth
  timeout — resolved by the factory deadline rather than chasing either.
- Adjacent issues parked: none new.

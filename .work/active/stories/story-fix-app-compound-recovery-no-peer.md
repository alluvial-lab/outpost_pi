---
id: story-fix-app-compound-recovery-no-peer
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Compound network recovery no longer strands the live-device soak in no-peer

## Symptom

The 300-second live soak with seed `20260828` timed out after the scheduled
278-second `net_compound slicer=6905 timeout=5622 bandwidth=243` window.
`LiveDeviceHarness.waitOnlineAndLive` reported `StatusNoPeer` with the selected
room retained but no active session. The same recovery class fired with seed
`20260822` during the 180-second performance-discovery soak after a long relay
pause and network timeout. Replay, transcript projection, ordering, working,
and owner/pair identity oracles were clean before both recovery timeouts.

Historical evidence:
`.work/session-notes/live-soak-20260823T231732Z-20260828/` and
`.work/session-notes/perf-discovery-20260824/live-soak-180/`.

## Root cause

The explicit fault-recovery path first calls `ConnectionManager.disconnect`,
which intentionally publishes `StatusNoPeer`, and then reconnects. Before
`c1969a45`, the reconnect hedge stopped at the WebSocket-handshake boundary and
covered only the first retry. A socket that had sent relay auth but stalled
waiting for the first authenticated frame could therefore consume successive
full deadlines. The selected peer and room were not lost; the reconnect simply
failed to adopt an authenticated channel and receive the authoritative rooms
snapshot within the harness's 45-second recovery deadline, leaving the
intentional no-peer projection and `session=null` visible at timeout.

## Fix approach

The minimal production repair already landed in `c1969a45` while resolving the
same reconnect lifecycle defect: `WsTransport.connect` now keeps the connect
operation open until a validated post-auth relay frame arrives, cancellation
closes superseded sockets, fallback adoption waits for loser teardown, and
every retry in a transport-loss chain remains hedged. No additional production
mutation was justified after the requested deterministic seed passed on the
current tree.

## Regression test

`app/test/transport/connection_manager_test.dart` contains the transport-level
fails-before guards added with that repair:

- `auth-read stall stays hedged until a fallback authenticates` proves a stalled
  authenticated primary is replaced and the manager returns online.
- `authenticated primary cancels fallback before a second relay auth` proves a
  winning primary cannot be kicked by a late same-device fallback.

Both tests failed against the pre-repair implementation as recorded in
`story-fix-app-reconnect-hedge-auth-boundary-and-post-adoption-cancel`. The live
seed remains the end-to-end regression because the exact slicer/timeout/
bandwidth interaction depends on the device, relay, and toxiproxy stack.

## Implementation notes

**Execution capability:** `sol/high`, selected for a timing-sensitive transport
lifecycle diagnosis across historical captures, reconnect diffs, deterministic
live-device evidence, and the full Flutter verification surface.

**Files changed:** this story consumes
`idea-soak-compound-recovery-no-peer`; production code and its focused tests
were already present in `c1969a45`.

### Four-step confirmation

1. Both focused reconnect hedge tests pass individually.
2. `flutter analyze` passes and
   `flutter test --exclude-tags e2e --concurrency=2` passes (`940` tests).
3. `python3 e2e/live_soak.py --duration 300 --seed 20260828` passes with all
   scheduled faults applied, 13 clean soak checkpoints, zero outside-window
   churn clusters, and no invariant violation. Evidence:
   `.work/session-notes/live-soak-20260824T193358Z-20260828/report.md`.
4. The reported contract is restored: the compound window recovers to an
   online live room with a non-empty active session; selection, pair identity,
   channel identity, replay, projection, and ordering remain stable.

`e2e/expected-soak-findings.txt` remains empty. No adjacent issue was bundled.

## Bounded inline review

**Verdict: pass — no material blockers.** The historical status trace was
checked against the soak's explicit disconnect/reconnect sequence and the
`c1969a45` auth-read/cancellation diff. The root cause is recovery latency and
socket ownership, not peer-selection loss. Existing loopback tests cover the
failure boundary, and the requested live seed provides end-to-end confirmation;
adding a second production change after a green reproduction would be
speculative rather than minimal.

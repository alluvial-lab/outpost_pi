---
id: story-fix-app-reconnect-hedge-auth-boundary-and-post-adoption-cancel
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-24
updated: 2026-08-24
---

# Reconnect hedge misses the auth-read stall and mis-cancels after adoption (supersede churn)

## Symptom
Operator UAT capture `app-capture-2026-08-24T08-58-48-427Z-dd9fe9d1c3c6`
(0.7.2+14, 08:52-08:58Z) + relay `relay.log.2026-08-24`. Two visible flake
shapes, both traced to the 0.7.0 3s fallback hedge (c9d08a7f):

1. **~30s reconnect stalls** (08:53:44→08:54:14, 08:55:39→08:56:07): three
   sequential full-deadline attempts; NO early fallback adoption. The
   stalled attempts complete the WS handshake and hang awaiting auth
   (TimeoutException ~11-13s each) — the hedge does not cover the
   auth-read boundary, only connect-stalls.
2. **Supersede churn** (08:56:16-08:56:21, five 1-2s cycles): relay log
   shows `authenticated … superseded_existing=true` pairs 1.3s apart —
   the fallback fires AFTER the primary adopted (cancel loses the race),
   the relay closes the live socket (`duplicate auth; closed prior`),
   the app reads channelDone → reconnect → re-arm → loop.

Working-state convergence held throughout (0 flaps — 7b993cf5 works);
data oracles clean; 5 of 7 drops healed in 1-2s.

## Root cause
`connection_manager.dart` hedge design: (a) triggers only while the
connect future is unresolved — a completed handshake stalled on auth read
is outside its scope; (b) the fallback's in-flight socket is not
teared-down deterministically when the primary wins adoption — a late
fallback auth supersedes the adopted channel relay-side.

## Fix approach
- Extend hedge coverage: if no AUTH COMPLETE within 3s of handshake (or
  unify: hedge until first authenticated frame), race a fresh connection.
- Adoption must atomically cancel + CLOSE the loser's socket before the
  winner is pronounced online (cancel token + explicit channel close; the
  loser must never reach the relay's auth handler post-adoption).
- Regression tests (fails-before): (1) handshake-completes-auth-stalls →
  online within ~4s simulated; (2) primary adopts at 1s, fallback timer
  fires at 3s → assert NO second authenticated socket ever reaches the
  fake relay (transport-level assertion, not just local state).

## Verification notes
Live: churn cluster recovery ≤5s across a soak with scheduled faults;
relay log shows zero `superseded_existing=true` outside fault windows.
Field re-check via operator capture (flap/recovery table like 08:52's).
Routes to the next release (v0.7.0 already tagged; this is the first
post-tag finding).

## Implementation

**Execution capability:** `sol/high`, selected for the timing-sensitive transport lifecycle and real-device verification surface. Direct implementation stayed within the app reconnect boundary; no independent reviewer was used because this is a standalone fix story.

### Changes

- `WsTransport.connect` now waits for a validated post-auth relay frame. It sends an empty, schema-valid `presence_check` as the ordered readiness probe, so an auth-handler stall remains inside the hedge window without consuming the later real hydration snapshot.
- `CancelToken` now exposes awaitable cooperative teardown through a narrow `ConnectionCancellation` port. `WsTransport` retains that listener through factory handoff and detaches it on close.
- Every retry in a transport-loss recovery chain remains hedged. Starting the fallback closes the primary first; selecting a winner cancels and awaits every loser close before completing the winner and publishing `StatusOnline`.
- Production and live/E2E reconnect factories pass their attempt cancellation into `WsTransport`.
- Removed this story from `e2e/expected-soak-findings.txt`; the manifest guard now expects an empty known-open inventory.

### Regression evidence

Both transport-level tests in `app/test/transport/connection_manager_test.dart` failed before the repair:

- `auth-read stall stays hedged until a fallback authenticates` timed out waiting for the second authenticated socket because the primary was pronounced online immediately after sending auth.
- `authenticated primary cancels fallback before a second relay auth` observed `StatusOnline` where `StatusConnecting` was required before the relay released the first authenticated response.

After the repair, both pass. The loopback fake relay proves the stalled primary is replaced within the bounded hedge and that allowing the primary to authenticate before the fallback deadline leaves the relay auth count at exactly one.

### Verification

- `flutter analyze`: no issues.
- `flutter test --exclude-tags e2e --concurrency=2`: green (`930` passed, `1` benchmark scaffold skipped).
- `python3 -m unittest` soak inventory guards: green.
- `e2e/run-live.sh state-shapes`: green (`3` tests).
- `python3 e2e/live_soak.py --duration 300 --seed 2026082411`: green. All transcript/data/identity oracles were clean; three observed transport losses recovered in `0.80–3.70s`, churn had one scheduled-fault cluster and zero outside-window clusters, and the relay log contained zero `superseded_existing=true` events.
- An earlier seed (`2026082407`) exposed an adjacent post-soak `working=false` quiescence timeout; parked as `idea-soak-post-quiescence-working-stuck`. The reconnect churn and data oracles in that run were otherwise clean.

### Bounded inline review

**Verdict: pass — no material blockers.** Reviewed the final diff for auth-read readiness, loser socket ownership, cancellation/dispose behavior from `cc66ccfa`, hydration dedup interaction, malformed readiness frames, and retry-chain convergence. The readiness completer accepts only validated control/data frames, the empty probe cannot suppress the subsequent peer hydration reply, and cancellation remains attached through the factory-to-manager handoff.

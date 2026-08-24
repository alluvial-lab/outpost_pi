---
id: story-fix-app-reconnect-hedge-auth-boundary-and-post-adoption-cancel
kind: story
stage: implementing
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

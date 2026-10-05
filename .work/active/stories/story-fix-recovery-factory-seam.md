---
id: story-fix-recovery-factory-seam
kind: story
stage: done
tags: [app, bug]
parent: null
depends_on: []
release_binding: v0.12.1
gate_origin: null
created: 2026-10-04
updated: 2026-10-04
---

# Recovery classification must survive the factory seam (pre-upgrade hang + hedge cancel)

## Brief — UAT round 1 (rc.1, capture 23:16:46 + relay logs)

Attribution fix verified in the field (both strikes report
`streamError`/`dartProtocolError`). The recovery fast-cycle NEVER engaged:
production wedge attempts are `hello → closeInitiated` at +3s (hedge
fallback cancelling the primary) or hang PRE-UPGRADE (relay saw zero hellos
23:01–23:12 — full dead path, unlike verdict #9's half-dead shape), then
surface as the factory's `_CancelledError`/`TimeoutException` (transport
kind) at +10–13s. The transport-owned 9s auth deadline loses every race:
disarmed at the +3s hedge cancel, or beaten by the factory's 10s candidate
timeout on pre-upgrade hangs. Ladder climbed 1→30s, 11× `_CancelledError`,
recovery ≈ wedge duration (11 min / 4 min).

## Fix design

A candidate that never produced a delivered frame is the wedge signal AT THE
FACTORY, whatever ends it:

1. `WsTransport.cancelConnect` error sites classify zero-inbound
   cancellations as `handshakeStall` (a hedge-cancelled candidate with zero
   inbound frames carries the signal out through its own rejection).
2. `ProductionConnectionFactory`:
   - candidate timeout rethrows with `kind: handshakeStall` (no channel ⇒
     no frames observed; safe even for slow-but-alive relays — worst case
     one extra fast retry);
   - the catch block keeps the candidate's own classified error instead of
     masking it with the generic `_CancelledError` when the parent token is
     cancelled.
3. Hard user cancels (disconnect/teardown) never route retries (cancelled
   tokens don't schedule), so relabeling their kinds is inert.

## Acceptance

- Red-first repro tests: (a) pre-upgrade-hang server (TCP accepts, upgrade
  never answered) + transport cancel ⇒ `handshakeStall`; (b) factory
  connector that never settles ⇒ factory timeout error carries
  `handshakeStall`; (c) hedge-cancelled zero-inbound candidate ⇒ classified
  error survives (not masked by `_CancelledError`).
- Full app suite green; rc.2 field criteria unchanged (fast-cycle visible in
  captures: stall-kind failures, 1s delayMs, no `_CancelledError` chains).

## Verification evidence

(accumulates)

## Verification evidence (2026-10-04)

Red-first repro (all three failed against pre-fix code, pass after):
- (a) pre-upgrade hang (TCP accepted, upgrade never answered) + transport
  cancel ⇒ `handshakeStall` — surfaced a REAL second bug: `ws.sink.close()`
  on a never-upgraded socket never settles; connect-phase cleanup now bounds
  it (2s) and the channel's internal `ready` future is ignored (late
  rejection surfaced as an unhandled zone error).
- (b) factory candidate timeout ⇒ error carries `handshakeStall`
  (timeout = zero frames delivered by definition).
- (c) classified candidate error survives parent cancellation — including
  the multi-candidate loop-top path (a recorded `WsTransportError` breaks
  out instead of being masked by the generic cancel).

Fix set: `production_connection_factory.dart` (candidate-timeout
classification + catch/loop-top precedence; `candidateTimeout` injectable),
`ws_transport.dart` (cancel-path zero-inbound classification, bounded
connect-phase sink close, `ws.ready.ignore()`).

Targeted suites: 51 tests green (factory, close-diagnostics, manager,
adapter); analyze clean.

## Review
Bounded inline pass over `3b2e5a814`: timeout classification and cancel
precedence verified against the catch/loop-top paths (classified error wins
via break → throwWithStackTrace); bounded close leaves only a dead
pre-auth socket orphan (documented); ready.ignore is contract-neutral (the
stream/sink own completion). Full suite 1,076 green. Verdict: pass.

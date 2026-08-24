# Pattern: Explicit Async Interleaving Tests

## Rationale

Lifecycle, stale-owner, and settlement-order defects live in the interleaving
of async operations — not in their eventual states. Tests that rely on
elapsed time (sleeps, real timers) to reach those interleavings are flaky
under scheduler load and often never observe the defect at all. Instead,
give the fake or harness explicit "started" and "release" gates: wait until
the operation reaches the controlled boundary, perform the competing
lifecycle action or intermediate assertion, then release the blocked work.
Production behavior stays real; timing becomes deterministic.

## When to use

Use this pattern for regression tests targeting stale-generation completion,
disposal mid-operation, deferred settlement, reconnect/rotation races, and
cleanup-order contracts.

1. Expose a controllable barrier at the narrowest fake or E2E-host boundary
   (a completer in a fake store, a deferred-turn control in the pi-host
   runtime).
2. Wait for the named checkpoint ("persistence started", "turn deferred").
3. Trigger the invalidation (retry, dispose, rotation) or assert the
   intermediate state (pending id, timer disarmed, no duplicate row).
4. Release the gate and assert exactly-once terminal behavior.

## When not to use

Do not use for ordinary eventual-state tests where a plain `await` suffices,
and never expose the barrier as a production API — it belongs to the fake or
the test harness seam.

## Examples

### Completer-gated persistence fences a stale pairing attempt

**File:** `app/test/ui/pairing/pairing_viewmodel_test.dart:421,452` — a fake
`savePairedPeer` blocks on a completer; the test calls `retry()`/`dispose()`
mid-await, releases, and asserts no durable peer, closed attempt-local
transport, and no stale emit.

### Deferred-turn settlement through the E2E pi-host

**File:** `pi-extension/test/support/e2e_pi_host_runtime.ts:269-287` and
`app/test/e2e/session_replacement_e2e_test.dart:123` — the harness exposes an
explicit arm/release barrier:

```ts
deferNextTurn(reply?: string): PiHostTurnControlStatus {
  this.stagedReply = reply ?? null;
  this.turnControlPhase = "armed";
  return this.turnControlStatus();
}

resolveDeferredTurn(): PiHostTurnControlStatus {
  if (this.turnControlPhase !== "pending" || !this.deferredTurnResolve) {
    throw new Error("no deferred turn is pending");
  }
  const resolve = this.deferredTurnResolve;
  this.deferredTurnResolve = null;
  resolve();
  return this.turnControlStatus();
}
```

The test asserts the original `cli_` id confirmation and timer disarm BEFORE
resolving, then asserts exactly one transcript row without sleeping.

## Common violations

- Replacing a sleep with a longer sleep instead of a deterministic barrier.
- Gating inside production code rather than at the fake/harness boundary.
- Asserting only the terminal state, leaving the intermediate ordering (the
  actual defect surface) unobserved.

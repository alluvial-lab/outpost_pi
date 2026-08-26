# Pattern: Deterministic Completion Barriers

## Rationale

Asynchronous tests often need to observe a queue, stream callback, detached write,
or projection after it has been scheduled but before wall-clock timers advance.
Use an explicit completion barrier: yield only to the event loop, or poll a
named semantic condition with a hard timeout. This makes completion ordering
visible without turning an arbitrary sleep into the test's synchronization
contract.

## When to use

Use for test-only completion of event-loop work such as stream delivery, queued
persistence, outbox confirmation, or turn-state convergence:

1. Use a zero-delay event-loop drain when the operation has a bounded known queue
   of microtasks/event turns.
2. Use a named state predicate when completion has a variable number of async
   steps; include a reason and a hard timeout so a missing transition fails
   loudly.
3. Keep interleaving control separate: use an explicit started/release gate
   when the test must hold work open, rather than hoping a drain catches it.

## When not to use

Do not use a fixed wall-clock sleep to imply completion, and do not use a
completion barrier to replace a required started/release interleaving gate.
Do not poll an implementation detail when a user-visible, persisted, or
wire-visible condition is available.

## Examples

### Event-loop drain for SyncService queues

**File:** `app/test/data/sync/sync_service_test.dart:372-378`

```dart
Future<void> _settle() async {
  // Do not advance wall-clock timers; drain queued stream/write continuations.
  for (var turn = 0; turn < 100; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}
```

The shared helper completes detached SyncService writes and stream deliveries
without allowing a pending timeout to fire.

### Semantic outbox completion barrier

**File:** `app/test/data/sync/sync_service_test.dart:1360-1364`

```dart
await _waitUntil(
  () => messages(s.epk).singleOrNull?.pending == false &&
      outbox.deliveries.isEmpty,
  reason: 'echo confirmation and durable outbox removal',
);
```

The test waits for both visible confirmation and durable removal instead of
assuming that one event-loop turn means the recovery transition is complete.

### Turn-convergence barrier after a terminal frame

**File:** `app/test/data/sync/sync_service_test.dart:1148-1156`

```dart
await _settle();
appendGate.complete();
await hydration;
await _settle();

expect(workingEmissions, [true, false]);
```

The terminal `AgentDone` is allowed to converge before the gated hydration
continuation is released; the final drain then proves no stale working or
streaming completion remains.

### Extension dispatch queue drain

**File:** `pi-extension/src/extension/relay_transport.test.ts:54,168-169`

```ts
const flushDispatch = (): Promise<void> => new Promise((resolve) => setImmediate(resolve));

relay.emit("message", JSON.stringify({ type: "peer_online", peer: "owner-a" }));
await flushDispatch();
```

The test yields one scheduler turn to let the transport's dispatch queue run;
it does not sleep for an arbitrary duration.

## Common violations

- Replacing a missing state transition with a longer `Future.delayed`.
- Using `_settle()` while a test still needs to prove that a gated operation is
  pending, then accidentally releasing or racing the gate.
- Waiting for a single callback when durable outbox removal or turn idle state
  is the actual completion contract.
- Omitting a reason or timeout from a variable-length predicate wait, leaving a
  hung test with no diagnosis.

## Related

- `explicit-async-interleaving-tests.md` — holds an operation at a started
  boundary and releases it explicitly; this pattern drains after the boundary.
- `failure-first-regression-tests.md` — uses completion barriers to make the
  repaired transition observable.

## Index entry

- **deterministic-completion-barriers**: Drain event-loop work or await a named bounded state predicate instead of using arbitrary sleeps for async test completion.

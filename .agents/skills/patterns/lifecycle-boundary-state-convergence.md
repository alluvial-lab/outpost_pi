# Lifecycle-Boundary State Convergence

## Rationale

A replaced session, disposed owner, or stopped transport can leave the last live projection stuck in an active state because its normal terminal callback never arrives. Converge lifecycle-owned activity to its inactive state before tearing down the channel that carries the correction. This makes restart, replacement, and shutdown observable as ordinary state transitions instead of leaving stale working or background indicators behind.

## When to use

Use for state that drives a remote or persistent projection and whose normal completion event can be skipped:

1. Identify every active axis owned by the lifecycle (for example turn work and background subagents).
2. Reset each axis at the replacement or disposal boundary.
3. Publish the correction while the outbound transport is still usable.
4. Tear down subscriptions, sockets, and timers only after the correction has been attempted.
5. Keep the reset idempotent and edge-triggered so already-idle state does not create noise.

## When not to use

Do not publish a fabricated terminal event for work owned by a successor session. Do not delay transport teardown indefinitely waiting for a best-effort correction, and do not reset state belonging to another owner or session.

## Examples

### Example 1: Extension startup clears a predecessor's working projection

**File**: `pi-extension/src/extension/composition_root.ts:101-114`

```ts
ports.session.bindSessionContext(ctx);
ports.session.onSessionLifecycle?.(reason, tail(sessionId));
if (!epoch.isCurrent()) return;
// A new session is genuinely idle; clear stale state left by a killed predecessor.
ports.session.publishWorking(false);
```

The new owner publishes its known idle state after it wins ownership, rather than waiting for a terminal event from the old session.

### Example 2: Extension shutdown resets background and turn state before relay stop

**File**: `pi-extension/src/extension/composition_root.ts:148-167`

```ts
tracker.clearForSessionBoundary();
if (ownsTracker) tracker.dispose();
ports.session.resetTurnSnapshot();
ports.session.clearStaleContexts(reason);
ports.relay.detachCrossPcBridge();
const relayStop = ports.relay.stop();
```

Both active projections converge before the relay is stopped, so a killed or replaced run cannot strand `background=true` or `working=true` in relay metadata.

### Example 3: App disposal clears cached room activity before closing its channel

**File**: `app/lib/data/transport/connection_manager.dart:687-707`

```dart
_disposed = true;
_clearActiveRoomWorking();
_cancelRetry();
_cancelPing();
_watchdogTimer?.cancel();
// ... then close the active WebSocket and streams.
```

The app removes the local active-room working projection before cancelling transport ownership; the reset remains safe when the room is already idle.

### Example 4: Background tracker clears session-scoped ids at the lifecycle edge

**File**: `pi-extension/src/extension/background_activity.ts:50-55`

```ts
void clearForSessionBoundary(): void {
  if (this.disposed || this.activeIds.size === 0) return;
  this.activeIds.clear();
  this.emitChange();
}
```

The tracker emits one idle edge only when the session boundary actually had tracked activity.

## Common violations

- Relying only on `turn_end`, `agent_end`, or `subagents:completed` when shutdown can skip those callbacks.
- Closing the relay before sending the correction, making the reset invisible to subscribers.
- Clearing one activity axis while leaving a related background/turn projection active.
- Emitting repeated false corrections without an edge check.
- Resetting state after a new owner has already taken over, allowing an old lifecycle to clear successor state.

## Related

- `edge-triggered-convergence.md` — suppresses unchanged notifications at the state mutation boundary.
- `generation-fenced-async-ownership.md` — prevents stale asynchronous completions from mutating the successor owner.

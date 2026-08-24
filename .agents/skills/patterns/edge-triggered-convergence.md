# Pattern: Edge-Triggered Convergence

## Rationale

A convergence update should produce side effects only when the semantic value changes. Compare the incoming projection with the current value at the mutation boundary, return on equality, and notify/persist/publish only on the edge. This prevents duplicate rebuilds, storage churn, wire broadcasts, and repeated correction loops while still allowing a new authoritative value to converge downstream consumers.

## When to use

Use for immutable ViewModel state, room/session projections, liveness metadata, and SDK-to-relay broadcasts:

1. Compare at the owner that performs the mutation.
2. Keep the no-op path free of notifications and persistence.
3. Treat semantic equality—not object identity or event arrival—as the edge.
4. Add a test that sends the same value twice and proves only one side effect occurs.

## When not to use

Do not suppress events whose repeated delivery is itself the contract, such as heartbeats, retries, or audit records. Do not use equality suppression in place of stale-session or owner/channel validation; an equal stale value can still be unauthorized.

## Examples

### Example 1: Base ViewModels notify only on a new state

**File:** `app/lib/ui/core/viewmodel/viewmodel.dart:19-24`

```dart
void emit(T newState) {
  if (_state != newState) {
    _state = newState;
    notifyListeners();
  }
}
```

Every stateful screen gets the same edge-triggered notification boundary.

### Example 2: Room working projection persists only on a changed value

**File:** `app/lib/data/transport/connection_manager.dart:1208-1225`

```dart
if (list[idx].working == working) return;
list[idx] = list[idx].copyWith(working: working);
_logDebug(
  WorkingConvEvent(
    ts: DateTime.now(),
    room: roomId,
    working: working,
    reason: 'mark_room_working',
  ),
);
_scheduleRoomsEmit();
_scheduleRoomPersistence(key);
```

The expensive log, stream emission, and persistence are downstream of the edge check.

### Example 3: Extension working metadata publishes only on a transition

**File:** `pi-extension/src/session/sdk_session_projection.ts:950-954`

```ts
private publishTurnProjection(before: TurnProjection, after: TurnProjection): void {
  if (before.working === after.working) return;
  this.publishWorking(after.working);
}
```

Repeated SDK events that preserve the same working projection do not amplify relay metadata.

### Example 4: Adaptive selection avoids rebuilding the same detail pane

**File:** `app/lib/routing/adaptive.dart:251-265`

```dart
final c = _current;
if (c != null && c.ref == ref) {
  return; // no-op — avoids rebuilding the detail/master views
}
_current = SelectedSession(
  ref: ref,
  title: title,
  device: device,
  online: online,
);
notifyListeners();
```

Selection changes remain observable, but repeated snapshots for the selected session are absorbed at the state owner.

## Common violations

- Calling `notifyListeners`, persisting, or publishing before checking semantic equality.
- Comparing only object identity when two equivalent projections are reconstructed independently.
- Suppressing an event before validating that its owner/session/channel is current.
- Adding a second downstream deduplication layer while the owner still emits duplicate edges.

# Pattern: Awaited Pane Teardown Contract

## Rationale

A workspace projection owns live pane resources whose shutdown is asynchronous:
PTYs, RPC processes, stream subscriptions, watchers, and timers. Removing a
pane from the projection before awaiting its close prevents new lookups from
reaching a closing resource, while the returned `Future` gives project and
workspace shutdown a single completion boundary.

## When to use

Use this for a live tab or pane that owns asynchronous resources and can be
closed individually or as part of a larger workspace teardown.

1. Define `Future<void> close()` on the shared pane abstraction.
2. Each resource-owning subtype awaits its subscriptions/processes before
   delegating to the base close.
3. The projection removes the pane from its lookup map, then awaits `close()`.
4. Bulk disposal composes the same per-pane operation rather than bypassing it.

## When not to use

Do not introduce this contract for immutable descriptors or synchronous,
resource-free values. Do not leave a closing pane addressable merely to avoid
awaiting its owned resources.

## Examples

### Shared pane boundary declares asynchronous close

**File:** `cockpit/lib/app/cockpit/ui/session/pane_item.dart:27`

```dart
Future<void> close() async {
  super.dispose();
}
```

### Agent session makes close idempotent and awaits owned resources

**File:** `cockpit/lib/app/cockpit/ui/session/agent_session.dart:493-504`

```dart
Future<void> close() {
  final closing = _closeFuture;
  if (closing != null) return closing;
  _closed = true;
  return _closeFuture = _closeResources();
}

Future<void> _closeResources() async {
  await _process.dispose();
  await _signalSub?.cancel();
  _signalSub = null;
  await super.close();
}
```

### Terminal session awaits its stream and child process before base close

**File:** `cockpit/lib/app/cockpit/ui/session/terminal_session.dart:128-134`

```dart
@override
Future<void> close() async {
  await _sub?.cancel();
  _sub = null;
  await _gateway.kill();
  await super.close();
}
```

### Projection removes ownership before awaiting pane teardown

**File:** `cockpit/lib/app/cockpit/ui/viewmodels/workspace_projection.dart:296-302`

```dart
Future<void> disposeTab(String id) async {
  final watcher = _fileWatchers.remove(id);
  _fileWatchDebounce.remove(id)?.cancel();
  final item = _items.remove(id);
  await watcher?.cancel();
  await item?.close();
}
```

## Common violations

- Calling a pane close method without awaiting it, allowing the workspace to
  declare shutdown complete while a process or subscription remains live.
- Clearing all maps before reusing the per-pane close path, which bypasses
  resource-specific teardown.
- Removing a pane only after awaited cleanup, leaving a closing resource
  discoverable by concurrent UI work.

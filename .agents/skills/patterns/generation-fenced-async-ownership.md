# Pattern: Generation-Fenced Async Ownership

## Rationale

A mobile or transport lifecycle can change while an awaited storage, transport,
or platform operation is in flight. The owner records a monotonically increasing generation
before starting the operation, invalidates it on replacement or disposal, and
checks it again before each side effect. A transport may pair that predicate
with an `AbortController`: abort actively tells handler-owned I/O to stop, while
the generation/current check remains the authority that suppresses stale
completions. This prevents stale work from installing subscriptions, publishing
state, sending to a replacement session, or writing a newer owner's cache.

## When to use

Use this pattern when an async operation belongs to a replaceable or disposable
owner: router boot, selected-chat binding, session synchronization, mesh pull,
or per-peer persistence.

1. Capture the generation (and, where applicable, the session/owner identity)
   before the first async gap.
2. Increment the generation when a retry, replacement, or disposal supersedes
   prior work.
3. Revalidate after every async gap before mutating state, installing a
   subscription, sending, or beginning a durable write.

## When not to use

Do not add a generation fence to a one-shot operation whose result is independent
of lifecycle state. Do not use it to imply cancellation of an already-entered
platform write; it prevents later side effects, not necessarily the I/O itself.

## Examples

### Router boot owns only its current continuation

**File:** `app/lib/routing/app_router.dart:83-102`

```dart
final generation = ++_generation;
_ready = false;
_failure = null;
_loading = true;

try {
  await prefs.load();
} on Object {
  _fail(generation, BootFailureStage.preferences, 'Could not load app settings. Try again.');
  return;
}
if (!_isCurrent(generation)) return;
```

### Chat initialization prevents stale session installation

**File:** `app/lib/ui/chat/viewmodels/chat_viewmodel.dart:183-201`

```dart
Future<void> _initializeRun(int generation) async {
  await _cancelProjectionSubscriptions();
  if (!_isCurrentRun(generation)) return;

  final peer = await _storage.loadPeer(epk);
  if (!_isCurrentRun(generation)) return;
  if (peer == null) {
    _bootstrapping = false;
    _initialized = true;
    emit(const ChatNoPeer());
    return;
  }
}
```

### Sync activation fences each durable hydration phase

**File:** `app/lib/data/sync/sync_service.dart:363-413`

```dart
if (nextRef != null) {
  await _loadIndex(nextRef, generation);
  if (!_isCurrentLifecycle(generation, nextRef)) return;
  await _rebuildTranscriptProjectionForRef(nextRef, generation);
  if (!_isCurrentLifecycle(generation, nextRef)) return;
  await _bindIdentityPendingSends(nextRef, generation);
  if (!_isCurrentLifecycle(generation, nextRef)) return;
  await _resendHeldPendingMessages(generation, nextRef);
  if (!_isCurrentLifecycle(generation, nextRef)) return;
}
_emitIdentityPendingMessages();
_writeRuntime();
```

### Mesh pull validates its mutation revision throughout cache replacement

**File:** `app/lib/data/mesh/mesh_sync_service.dart:324-407`

```dart
bool current() =>
    _isPullCurrent(mutationRevision, allowPendingMutation, expectedOwnerPk);

final peers = await _storage.listPeers();
if (!current()) return false;
```

The member and deletion loops at the same anchor repeat `current()` checks
before each mutation and after every awaited save/delete, ending with
`return current();`.

### Owner outbox send fences persistence and channel replacement

**File:** `app/lib/data/sync/sync_service.dart:520-539,588-595`

```dart
await _ownerDeliveryOutbox.upsert(delivery);
if (!_isCurrentLifecycle(generation, ref) ||
    !identical(_conn.channel, initialChannel) ||
    (!held && !_conn.isRoomLive(ref.peerEpk, ref.roomId))) {
  _retainReconnectRacedSend(/* ... */);
  return;
}
```

The send captures both lifecycle generation and channel before awaited outbox
persistence, then revalidates them before choosing a channel write. A reconnect
cannot turn a durable intent into an untracked send on a dead or replacement
socket.

### Relay dispatch pairs AbortSignal with a current-generation predicate

**File:** `pi-extension/src/extension/relay_transport.ts:219-222,247,331-337`

```ts
function connectionIsCurrent(binding: RelayBinding): boolean {
  return relayBinding?.generation === binding.generation &&
    relay === binding.relay && !stopping && !isDisposed?.();
}

const dispatchAbort = new AbortController();
// on unbind: dispatchAbort.abort(); queued work is released
```

Each relay binding owns a generation and abort signal. Unbinding aborts active
handler I/O and releases queued work; handlers still receive
`connectionIsCurrent` so a late completion cannot publish stale effects.

## Common violations

- Checking only at method entry, then mutating after an await with a stale
  generation.
- Incrementing a generation on retry but not disposal or session replacement.
- Checking a generation without also checking the captured session, channel, or
  owner identity when that identity can change independently.
- Treating a fence as cancellation and assuming an already-started write did
  not reach storage.

## Index entry

- **generation-fenced-async-ownership**: Capture a lifecycle revision before async work and suppress side effects when the owner has been replaced or disposed.

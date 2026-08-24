# Pattern: Generation-Fenced Async Ownership

## Rationale

A mobile lifecycle can change while an awaited storage, transport, or platform
operation is in flight. The owner records a monotonically increasing generation
before starting the operation, invalidates it on replacement or disposal, and
checks it again before each side effect. This prevents stale completions from
installing subscriptions, publishing state, sending to a replacement session, or
writing a newer owner's cache.

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

**File:** `app/lib/data/sync/sync_service.dart:338-385`

```dart
if (nextRef != null) {
  await _loadIndex(nextRef, generation);
  if (!_isCurrentLifecycle(generation, nextRef)) return;
  await _materializeTranscriptProjectionForRef(nextRef, generation);
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

for (final m in blob.members) {
  if (!current()) return false;
  // Build the canonical survivor-aware `next` record.
  if (prev == null || !_peerEqualsForMesh(prev, next)) {
    await _storage.saveMeshPeerMetadata(next);
    if (!current()) return false;
  }
}

await _storage.deleteRooms(p.remoteEpk);
if (!current()) return false;
return current();
```

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

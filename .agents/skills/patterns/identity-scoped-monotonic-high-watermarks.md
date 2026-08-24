# Identity-Scoped Monotonic High-Watermarks

Bind persisted high-watermarks to their owner or key generation, advance them monotonically under serialization, and reject stale or lower values.

## Rationale

Owner-channel sequence numbers and mesh versions are security state, not ordinary cache values. A stale process or replaced key generation must not lower or advance another identity's watermark. Durable comparison and mutation therefore occur in one serialized or locked operation.

## Examples

### Example 1: App channel counters merge only under matching directional keys
**File**: `app/lib/pairing/storage.dart:570-598`
```dart
Future<void> saveChannelState(
  String remoteEpk,
  OwnerChannelState channel,
) => _serializePeerMutation(() async {
  if (await _store.read(key: _peerKey(remoteEpk)) == null) {
    throw StateError('cannot persist channel state for an unknown peer');
  }
  final channelKey = _channelKey(remoteEpk);
  final currentRaw = await _store.read(key: channelKey);
  if (currentRaw == null) {
    throw StateError('cannot update missing owner-channel material');
  }
  final current = OwnerChannelState.fromJson(
    jsonDecode(currentRaw) as Map<String, dynamic>,
  );
  if (current.sendKey != channel.sendKey ||
      current.receiveKey != channel.receiveKey) {
    throw StateError('owner-channel key changed during active connection');
  }
  final monotonic = channel.copyWith(
    sendSequence: current.sendSequence > channel.sendSequence
        ? current.sendSequence
        : channel.sendSequence,
    receiveSequence: current.receiveSequence > channel.receiveSequence
        ? current.receiveSequence
        : channel.receiveSequence,
  );
  await _store.write(key: channelKey, value: jsonEncode(monotonic.toJson()));
});
```
The actual method also rejects an unknown peer or missing channel before this
serialized, identity-checked merge.

### Example 2: Extension send reservations are fenced by the expected channel generation
**File**: `pi-extension/src/pairing/storage.ts:589-600`
```ts
reserveSendSeq(remoteEpk: string, expectedChannelKey: string): Promise<bigint | null> {
  return this.mutatePeers(async (peers) => {
    const peer = peers.find((candidate) => candidate.remote_epk === remoteEpk);
    if (!peer || peer.channel_key !== expectedChannelKey) return null;
    const stored = parsePeerChannelSequence(peer.send_seq);
    if (stored === null) return null;
    if (stored === MAX_UINT64) throw new RangeError("owner channel send sequence exhausted uint64");
    const reserved = stored + 1n;
    peer.send_seq = reserved.toString(10);
    await this.writePeersFile(peers);
    return reserved;
  });
}
```

### Example 3: Extension receive acceptance is the result of a locked compare-and-advance
**File**: `pi-extension/src/pairing/storage.ts:613-630`
```ts
return this.mutatePeers(async (peers) => {
  const peer = peers.find((candidate) => candidate.remote_epk === remoteEpk);
  if (!peer || peer.channel_key !== expectedChannelKey) return "stale_generation";
  const stored = parsePeerChannelSequence(peer.recv_seq);
  if (stored === null) throw new Error("persisted owner channel receive sequence is invalid");
  if (recvSeq <= stored) return "replay";
  peer.recv_seq = recvSeq.toString(10);
  await this.writePeersFile(peers);
  return "accepted";
});
```

### Example 4: Mesh state persists the owner-scoped version before adopting it
**File**: `app/lib/data/mesh/mesh_sync_service.dart:258-277`
```dart
var context = _latestContext(operationContext);
if (blob.version < context.highWatermark) {
  _diagnoseRollbackRejection();
  return false;
}
if (blob.version > context.highWatermark) {
  if (!current()) return false;
  await _storage.saveMeshHighWatermark(
    context.ownerPkHash,
    blob.version,
  );
  if (!current()) return false;
  context = _WatermarkContext(context.ownerPkHash, blob.version);
  _watermarkContext = context;
}
```

## When to Use
- Replay counters, mesh versions, epochs, or rollback floors associated with a cryptographic identity or replaceable generation.
- When multiple processes or delayed writes can mutate the same durable state.

## When NOT to Use
- User-editable values or caches where moving backward is legitimate.
- Ephemeral counters that have no security or convergence meaning after restart.

## Common Violations
- A read-then-write sequence without shared serialization or a machine-wide lock.
- Updating a counter without checking its key/owner generation.
- Replacing a high-watermark with a stale lower snapshot.
- Dispatching a protected effect before the authoritative watermark write completes.

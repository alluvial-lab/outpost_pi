# Recoverable Secure-Channel Circuit Breakers

After a bounded streak of invalid established-channel frames, detach the transient adapter but retain persisted keys so authenticated traffic can reconnect and rehydrate state.

## Rationale

Continuing indefinitely after repeated AEAD, replay, or typed-payload failures wastes resources and obscures broken channels. Permanently deleting keys is also disproportionate: transport corruption or hostile traffic should recover through reconnect and `session_sync`, while re-pairing remains reserved for actual key loss.

## Examples

### Example 1: App closes after consecutive secure-frame failures
**File**: `app/lib/data/transport/peer_channel.dart:335-382`
```dart
final opened = await openOwnerChannelFrame(
  key: _receiveKey,
  frame: bytes,
  lastSequence: _receiveSequence,
);
if (opened == null) {
  await _recordFailure('authentication_failed', bytes.length);
  return;
}

// A valid, durably accepted frame heals the failure streak.
await _persistState();
if (_closed) return;
_consecutiveFailures = 0;
if (!_controller.isClosed) _controller.add(message);

Future<void> _recordFailure(String kind, int bytes, {String? error}) async {
  _debugLog?.log(PeerFrameEvent(
    ts: DateTime.now(),
    kind: kind,
    bytes: bytes,
    error: error,
  ));
  _consecutiveFailures++;
  if (_consecutiveFailures >= _failureThreshold) await close();
}
```

### Example 2: Extension detaches after its protected-frame threshold
**File**: `pi-extension/src/transport/peer_channel.ts:508-519`
```ts
const opened = open(this.options.keys.recv, frame, this.recvSeq);
if (!opened) {
  this.consecutiveOpenFailures += 1;
  this.audit({
    reason: "open_failed",
    seq: frame.length >= 9
      ? new DataView(frame.buffer, frame.byteOffset + 1, 8).getBigUint64(0, true)
      : undefined,
    consecutiveFailures: this.consecutiveOpenFailures,
  });
  if (this.consecutiveOpenFailures >= MAX_OPEN_FAILURES) this.disconnect();
  return;
}
```

### Example 3: The next frame can recreate a channel from persisted keys
**File**: `pi-extension/src/extension/owner_multiplexer.ts:327-347`
```ts
const known = await this.deps.findKnownPeer(outer.peer);
if (!input.isCurrent() || this.channels.has(outer.peer)) return false;
if (known) {
  if (!known.channel_key) {
    this.deps.auditDrop(outer.peer, "missing_channel_key");
    return false;
  }
  this.attach({
    peerId: outer.peer,
    peerName: known.name,
    peerRecord: known,
    roomId: input.roomId,
    turnActive: input.turnActive(),
    onMessage: input.onMessage,
    onDisconnect: input.onDisconnect,
  });
  this.deps.onOwnerAttached({
    peerId: outer.peer,
    peerName: known.name,
    activeCount: this.activeCount(),
  });
  return false;
}
```

## When to Use
- Established encrypted channels where repeated invalid frames indicate a poisoned or unusable adapter.
- When reconnect plus authoritative synchronization can recover dropped application state.

## When NOT to Use
- Pre-key pairing traffic, where no established channel exists.
- Permanent key loss, malformed persisted key material, or identity replacement; those require re-pairing or explicit reset.
- Single isolated attacker failures that should simply be rejected.

## Common Violations
- Falling back to plaintext after detaching an encrypted channel.
- Deleting persisted keys on a transient failure streak.
- Reattaching before the prior channel generation's accepted persistence work drains.
- Forgetting to reset the streak after a valid, durably accepted frame.

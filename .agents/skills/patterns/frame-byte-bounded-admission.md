# Frame-and-Byte Bounded Admission

Bound burst-controlled queues by both item count and retained bytes before allocating or enqueueing work.

## Rationale

A frame-count limit alone permits a few huge messages to retain excessive memory; a byte-only limit permits floods of tiny promise continuations or queue cells. Owner-channel and relay queues consistently enforce both dimensions and account synchronously before asynchronous work is retained.

## Examples

### Example 1: App WebSocket inbound FIFO uses dual admission limits
**File**: `app/lib/data/transport/ws_transport.dart:572-584`
```dart
bool add(Uint8List msg) {
  if (_closed) return false;
  if (_waiters.isNotEmpty) {
    _waiters.removeAt(0).complete(msg);
    return true;
  }
  if (_buf.length >= maxFrames || msg.length > maxBytes - _pendingBytes) {
    _onOverflow?.call(msg.length);
    return false;
  }
  _buf.add(msg);
  _pendingBytes += msg.length;
  return true;
}
```

### Example 2: App secure-channel outbound work accounts before continuation allocation
**File**: `app/lib/data/transport/peer_channel.dart:265-286`
```dart
final json = encodeClient(msg).trimRight();
final jsonBytes = utf8.encode(json).length;
if (_pendingOutboundFrames >= _maxPendingOutboundFrames ||
    jsonBytes > _maxPendingOutboundBytes - _pendingOutboundBytes) {
  return _closeForOutboundOverflow();
}

// Account before allocating the continuation that retains [json].
_pendingOutboundFrames++;
_pendingOutboundBytes += jsonBytes;
final operation = _sendTail.then((_) => _sendOne(json));
_sendTail = operation.catchError((Object _) {}).whenComplete(() {
  _pendingOutboundFrames--;
  _pendingOutboundBytes -= jsonBytes;
});
```

### Example 3: Extension relay dispatch independently budgets control and data
**File**: `pi-extension/src/extension/relay_transport.ts:382-416`
```ts
if (controlFrame) {
  if (
    pendingControlFrames >= MAX_PENDING_RELAY_CONTROL_FRAMES ||
    lineBytes > MAX_PENDING_RELAY_CONTROL_BYTES - pendingControlBytes
  ) {
    recordOverflow(controlOverflow, lineBytes);
    return;
  }
  enqueue({
    queue: "control",
    lineBytes,
    line: null,
    controlFrame,
    accounted: true,
  });
  return;
}

if (
  pendingDataFrames >= MAX_PENDING_RELAY_DISPATCH_FRAMES ||
  lineBytes > MAX_PENDING_RELAY_DISPATCH_BYTES - pendingDataBytes
) {
  recordOverflow(dataOverflow, lineBytes);
  return;
}
```

## When to Use
- Any queue retaining wire frames, serialized messages, promises, or attacker-influenced work.
- When accepted order matters and overflow must not evict an arbitrary accepted suffix.

## When NOT to Use
- A fixed-size queue whose elements are genuinely uniform and independently size-capped.
- Stateless one-shot work that is not retained across an async boundary.

## Common Violations
- Limiting only frame count or only bytes.
- Incrementing accounting after allocating the promise or queue cell.
- Failing to decrement accounting on error, cancellation, unbind, or teardown.
- Silently dropping part of an accepted ordered stream without triggering documented recovery.

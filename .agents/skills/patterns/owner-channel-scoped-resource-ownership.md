# Pattern: Owner-Channel-Scoped Resource Ownership

## Rationale

A resource attached to a remote owner is not safely identified by owner id alone: the same owner can reconnect with a replacement channel while work from the old channel is still settling. Retain both dimensions, require both to match before accepting or mutating the resource, and remove every owner/channel index on detach. This prevents stale channel callbacks from consuming, replying to, or tearing down a successor's state.

## When to use

Use for uploads, subscriptions, buffers, channel listeners, and per-owner fanout state that can outlive one callback or reconnect attempt:

1. Record the owner identity and the concrete channel handle together.
2. Match both when routing a continuation or releasing retained state.
3. Remove the owner and reverse-channel indexes as one teardown operation.
4. Treat a callback from a non-current channel as stale, not as evidence that the current owner is offline.

## When not to use

Do not use owner/channel matching as a replacement for cryptographic authentication, durable key-generation checks, or an async lifecycle generation fence. Use those complementary boundaries where the resource crosses storage or awaits replacement-sensitive work.

## Examples

### Example 1: Capture upload admission requires owner, channel, and upload id

**File:** `pi-extension/src/actions/capture_upload_handler.ts:27-34,89-100,283-291`

```ts
interface UploadState {
  readonly ownerId: string;
  readonly channel: CaptureReplySender;
  // ... upload id and retained bytes
}

detachChannel(ownerId: string, channel: CaptureReplySender): void {
  if (this.active?.ownerId === ownerId && this.active.channel === channel) {
    this.active = null;
  }
}

private ownedActive(ownerId: string, channel: CaptureReplySender, uploadId: string) {
  const active = this.active;
  return active?.ownerId === ownerId && active.channel === channel && active.id === uploadId
    ? active
    : null;
}
```

A replacement channel cannot append to or clear an upload owned by its predecessor.

### Example 2: Multiplexer keeps forward and reverse channel indexes in sync

**File:** `pi-extension/src/extension/owner_multiplexer.ts:211-213,489-511,550-552`

```ts
private readonly channels = new Map<string, PeerChannelHandle>();
private readonly peerIdsByChannel = new Map<PeerChannelHandle, string>();
private readonly messageRouters = new Map<PeerChannelHandle, OwnerAttachInput["onMessage"]>();

this.channels.set(input.peerId, channel);
this.peerIdsByChannel.set(channel, input.peerId);
this.messageRouters.set(channel, input.onMessage);

this.channels.delete(peerId);
this.peerIdsByChannel.delete(channel);
this.messageRouters.delete(channel);
```

The owner id selects the logical channel while the concrete handle selects the callback route; attach and detach update both views together.

### Example 3: Connection loss acts only on the active channel instance

**File:** `app/lib/data/transport/connection_manager.dart:1584-1623`

```dart
void _onChannelLost(PeerRecord peer, IChannel ch, {ReconnectCause cause = ReconnectCause.unknown}) {
  if (_status is! StatusOnline) return;
  final cur = (_status as StatusOnline).channel;
  if (!identical(cur, ch)) {
    // This close belongs to a channel already replaced by a retry.
    return;
  }
  _cancelPing();
  _reachability.onTransportClosed();
  _scheduleRetry(peer);
}
```

The old channel's `onDone` cannot schedule a retry against the replacement channel.

### Example 4: Durable channel state is keyed and validated by its paired peer

**File:** `app/lib/pairing/storage.dart:352-354,570-597`

```dart
String _peerKey(String remoteEpk) => '$_kPeersService:$remoteEpk';
String _channelKey(String remoteEpk) => '$_kChannelsService:$remoteEpk';

final current = OwnerChannelState.fromJson(
  jsonDecode(currentRaw) as Map<String, dynamic>,
);
if (current.sendKey != channel.sendKey ||
    current.receiveKey != channel.receiveKey) {
  throw StateError('owner-channel key changed during active connection');
}
```

Peer metadata and owner-channel secrets share the peer identity but remain separate records, so a delayed metadata write cannot replace the active channel keys.

## Common violations

- Keying an in-flight resource by owner id or upload id alone.
- Deleting the owner map but leaving the reverse channel map or listener subscription alive.
- Treating any channel close for an owner as the current channel's close.
- Clearing a successor's state from a stale callback because identity was checked before, but not at teardown.

# Evidence-Local Failure Classification

Assign recovery categories at the boundary that observes the discriminating
evidence; downstream policy consumes those categories rather than
reconstructing causes.

## Rationale

Transport, HTTP, and storage boundaries observe different evidence:
inbound-frame counts, response status, or missing persisted keys. Flattening
these observations into generic exceptions loses information needed for retry
and recovery decisions.

This complements — does not duplicate — `content-free-diagnostic-categories`:
that pattern governs safe logging; this pattern governs ownership of
operational classification. It extends beyond wire decoding to local
persistence.

## Examples

### 1. Classify a handshake failure using the socket's own inbound history

**File**: `app/lib/data/transport/ws_transport.dart:264`

```dart
ReachabilityFailureKind preAuthFailureKind(
  ReachabilityFailureKind framesSeenKind,
) => transport._inboundFrameCount == 0
    ? ReachabilityFailureKind.handshakeStall
    : framesSeenKind;
```

The transport attaches this category to `WsTransportError`.
`ConnectionManager` consumes it through `classifyWsTransportFailure`
(`app/lib/data/transport/connection_manager.dart`); `ReachabilityAdapter`
selects the retry delay without inspecting socket internals.

### 2. Translate HTTP response status into operational outcomes

**File**: `app/lib/data/mesh/mesh_client.dart:253`

```dart
case 400:
  return MeshPublishBadRequest(_extractMessage(response.data));
case 403:
  return const MeshPublishForbidden();
case 409:
  return const MeshPublishConflict();
case 413:
  return const MeshPublishTooLarge();
```

The mutation coordinator switches on these result types
(`app/lib/data/mesh/mesh_sync_service.dart`), distinguishing retryable
outcomes from permanent failures without importing HTTP status handling.

### 3. Distinguish an absent provisioned key from unsuccessful persistence

**File**: `app/lib/data/local/transcript_storage_key.dart:49`

```dart
final stored = await _store.read();
if (stored != null) return _decode(stored);
if (keyWasProvisioned) {
  throw const TranscriptStorageKeyException('missing_provisioned_key');
}
final encoded = base64Encode(Hive.generateSecureKey());
await _store.write(encoded);
final persisted = await _store.read();
if (persisted == null) {
  throw const TranscriptStorageKeyException('key_write_not_persisted');
}
```

The exception's recovery predicate distinguishes discard-eligible failures;
bootstrap consumes that predicate (`app/lib/main.dart`) rather than probing
storage again or matching exception messages.

## When to Use

- Recovery depends on evidence unavailable to the caller.
- Infrastructure-specific observations must drive domain retry or recovery
  policy.
- Several consumers need the same classification without duplicating
  inference.

## When NOT to Use

- The boundary lacks sufficient evidence to distinguish causes; preserve an
  unknown category.
- The caller already receives an authoritative typed outcome.
- A category would merely rename an exception without changing handling.

## Common Violations

- Matching exception text upstream to infer transport or storage state.
- Discarding a typed category when wrapping an exception.
- Letting an outer generic timeout erase a more informative boundary failure.
- Treating a useful operational category as proof of an underlying physical
  cause.

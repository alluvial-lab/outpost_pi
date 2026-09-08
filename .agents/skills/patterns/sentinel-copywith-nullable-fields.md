# Sentinel CopyWith for Nullable Fields

## Rationale

Dart's nullable named parameters cannot distinguish an omitted argument from an explicit `null`. Immutable models that need both operations must use a private sentinel as the default for nullable `copyWith` parameters, then compare by identity: the sentinel means preserve the current value, while `null` means clear it. This keeps partial room patches and persisted-record updates lossless without inventing a second update method.

## Examples

### Example 1: Room metadata preserves or clears additive telemetry fields

**File**: `app/lib/protocol/control_frames.dart:288-320`

```dart
RoomInfo copyWith({
  Object? branch = _kRoomInfoUnset,
  Object? ctxPercent = _kRoomInfoUnset,
  Object? ctxMax = _kRoomInfoUnset,
}) => RoomInfo(
  // ...
  branch: identical(branch, _kRoomInfoUnset)
      ? this.branch
      : branch as String?,
  ctxPercent: identical(ctxPercent, _kRoomInfoUnset)
      ? this.ctxPercent
      : ctxPercent as int?,
  ctxMax: identical(ctxMax, _kRoomInfoUnset)
      ? this.ctxMax
      : ctxMax as int?,
);
```

The merge-patch adapter can pass the sentinel for an omitted field and `null` for an explicit clear.

### Example 2: Persisted room records retain partial-update intent

**File**: `app/lib/pairing/storage.dart:75-94`

```dart
PersistedRoom copyWith({
  Object? sessionId = _unset,
  Object? localName = _unset,
  Object? model = _unset,
}) => PersistedRoom(
  // ...
  sessionId: identical(sessionId, _unset)
      ? this.sessionId
      : sessionId as String?,
  localName: identical(localName, _unset)
      ? this.localName
      : localName as String?,
  model: identical(model, _unset) ? this.model : model as String?,
);
```

Persistence migrations and reconciliation can clear nullable fields without treating an omitted field as a clear.

### Example 3: Pairing records apply the same sentinel to nullable objects

**File**: `app/lib/pairing/storage.dart:261-279`

```dart
PeerRecord copyWith({
  Object? nickname = _unset,
  Object? roomId = _unset,
  Object? harness = _unset,
  Object? channel = _unset,
}) => PeerRecord(
  // ...
  nickname: identical(nickname, _unset) ? this.nickname : nickname as String?,
  roomId: identical(roomId, _unset) ? this.roomId : roomId as String?,
  harness: identical(harness, _unset) ? this.harness : harness as PiHarness?,
  channel: identical(channel, _unset)
      ? this.channel
      : channel as OwnerChannelState?,
);
```

The same shape handles nullable scalar and nullable value-object fields while retaining an ordinary typed `copyWith` call site.

## When to Use

- Use for immutable Dart models whose nullable fields need both "leave unchanged" and "set to null" operations.
- Keep the sentinel private and compare it with `identical`, not equality or a nullable fallback.
- Pair the model helper with a boundary representation that tracks field presence, such as generated `hasField` flags for a wire patch.

## When NOT to Use

- Do not use it when `null` unambiguously means "preserve" or when the field is non-nullable.
- Do not use a sentinel to paper over a full authoritative replacement; model the replacement contract directly.
- Prefer a generated tri-state DTO or a dedicated patch type when the update is a public wire contract rather than an in-process immutable-model update.

## Common Violations

- Writing `field: value ?? this.field`, which makes explicit nullable clears impossible.
- Using a new sentinel object at each call site, so identity checks cannot recognize omission.
- Exposing the sentinel publicly or accepting arbitrary `Object` values without the cast at the model boundary.
- Adding a nullable field but forgetting to extend its `copyWith`, equality, hash, and patch-application paths together.

## Index entry

- **sentinel-copywith-nullable-fields**: Use a private identity sentinel so Dart copyWith distinguishes omitted nullable fields from explicit null clears.

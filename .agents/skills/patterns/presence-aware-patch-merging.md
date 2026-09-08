# Presence-Aware Patch Merging

## Rationale

Incremental metadata updates must distinguish an omitted field from an explicit value. A patch representation carries field presence separately from the field value, so consumers preserve cached state when a producer sends a partial update while still applying explicit `false`, `null`, or replacement values according to the field contract. The field categories must stay explicit as the contract grows: nullable strings, nullable integers, and non-nullable booleans each need the corresponding presence and clear semantics. The same rule keeps relay state, app room caches, and compatibility metadata convergent across mixed versions. When cached metadata projects live activity, current room liveness is the independent presence signal: do not treat a cached `background` or `working` value as authoritative until the relay confirms that room is live.

## When to use

Use for partial room/session metadata, persisted record updates, and other merge-style updates:

1. Represent presence independently when `null` is itself meaningful (for example `Option<Option<T>>`, a presence flag, or a sentinel).
2. Preserve the cached field when the patch omits it.
3. Apply explicit values, including `false` and explicit clears, rather than using truthiness or a null-coalescing default that loses intent.
4. Make full snapshots authoritative when their contract differs from incremental patches, and test both forms.
5. Gate cached live-state projections on an independent freshness/presence signal, such as current live-room membership after a transport reconnect.

## When not to use

Do not merge a full authoritative snapshot as though it were a partial patch. Do not use this pattern for immutable replacement values or fields whose wire contract makes absence and null identical. Do not infer presence from truthiness: `false`, `0`, and empty strings may be intentional values.

## Examples

### Example 1: Relay patch DTO preserves field presence and explicit nullable clears

**File**: `relay/src/protocol/generated/room.rs:29-39`

```rust
pub struct RoomMetaPatch {
    pub model: Option<Option<String>>,
    pub thinking: Option<Option<String>>,
    pub session_id: Option<Option<String>>,
    pub working: Option<bool>,
    pub background: Option<bool>,
}
```

The outer `Option` means the field was absent or present; the inner `Option` lets a present nullable string clear cached metadata. Boolean fields preserve absence while still accepting explicit `false`.

### Example 2: Relay applies only present fields to the canonical room record

**File**: `relay/src/peers/rooms.rs:78-105`

```rust
if let Some(model) = patch.model {
    meta.model = model;
}
if let Some(thinking) = patch.thinking {
    meta.thinking = thinking;
}
if let Some(session_id) = patch.session_id {
    meta.session_id = session_id;
}
if let Some(working) = patch.working {
    meta.working = working;
}
if let Some(background) = patch.background {
    meta.background = Some(background);
}
```

A partial `room_meta_update` cannot erase an unrelated cached field; explicit values are applied at the single canonical relay store.

### Example 3: App incremental updates preserve omitted room fields

**File**: `app/lib/data/transport/connection_manager.dart:1214-1224`

```dart
final nextSessionId = hasSessionId ? sessionId : current.sessionId;
final nextModel = hasModel ? model : current.model;
final nextThinking = hasThinking ? thinking : current.thinking;
final nextBackground = background ?? current.background;
final nextWorking = working ?? current.working;
```

The app uses presence flags for nullable string metadata and nullable-as-absent booleans. A model-only or thinking-only update therefore leaves the other cached values intact, while `working: false` remains an explicit off transition.

### Example 4: App room snapshots preserve local-only and legacy metadata selectively

**File**: `app/lib/data/transport/connection_manager.dart:1252-1277`

```dart
final preservedName = byId[r.roomId]?.name ?? r.name;
final preservedSessionId = r.sessionId ?? byId[r.roomId]?.sessionId;
final preservedModel = r.model ?? byId[r.roomId]?.model;
final preservedThinking = r.thinking ?? byId[r.roomId]?.thinking;
// The snapshot is authoritative for live state.
working: r.working,
background: r.background,
```

This deliberately separates compatibility preservation for omitted descriptive metadata from authoritative replacement of live state in a full snapshot.

### Example 5: Chat projection rejects cached background while the room is not live

**File**: `app/lib/ui/chat/viewmodels/chat_viewmodel.dart:138-147`

```dart
bool _backgroundProjection() {
  final peer = _activePeer;
  if (peer == null || !_conn.isRoomLive(peer.remoteEpk, _activeRoomId)) {
    return false;
  }
  return activeRoom?.background ?? false;
}
```

The chat status consumes `RoomInfo.background` only after the connection
manager's live-room set confirms the active room; reconnecting or stale cache
therefore cannot keep the background indicator active.

### Example 6: Home projection applies the same live-room gate to a second consumer

**File**: `app/lib/ui/home/viewmodels/home_viewmodel.dart:72-79`

```dart
bool isRoomOrchestrating(String epk, String roomId) {
  if (!_conn.isRoomLive(epk, roomId)) return false;
  for (final room in _conn.roomsFor(epk)) {
    if (room.roomId == roomId) return room.background;
  }
  return false;
}
```

The home tile uses the same freshness boundary before rendering its
orchestrating pulse. Both chat and home derive from cached room metadata, but
neither trusts it after disconnect until a live snapshot restores authority.

### Example 7: Schema metadata names the additive field categories

**File**: `protocol/schema/relay-control.schema.json:71-82`

```json
"branch": { "type": ["string", "null"], "maxLength": 256 },
"ctx_percent": { "type": ["integer", "null"], "minimum": 0, "maximum": 100 },
"ctx_max": { "type": ["integer", "null"], "minimum": 0 }
// x-outpost-pi.mergePatchSemantics:
// nullableStrings: [..., "branch"]
// nullableIntegers: ["ctx_percent", "ctx_max"]
// nonNullableBooleans: ["working", "background"]
```

The schema remains the single source of truth for whether omission preserves, null clears, or a boolean value sets a field. Adding branch and context usage extends the existing additive-room-metadata recipe without inventing a second patch contract.

### Example 8: Generated Rust keeps presence and null as two dimensions

**File**: `relay/src/protocol/generated/room.rs:44-54`

```rust
pub struct RoomMetaPatch {
    pub branch: Option<Option<String>>,
    pub ctx_percent: Option<Option<u64>>,
    pub ctx_max: Option<Option<u64>>,
    pub working: Option<bool>,
    pub background: Option<bool>,
}
```

The outer `Option` records wire presence, while the inner `Option` permits explicit null for the nullable string/integer fields. Booleans need only the outer presence layer.

### Example 9: App projection carries presence flags into one patch applicator

**File**: `app/lib/protocol/control_frames.dart:468-521`

```dart
final String? branch;
final int? ctxPercent;
final int? ctxMax;
final bool hasBranch;
final bool hasCtxPercent;
final bool hasCtxMax;

RoomInfo applyTo(RoomInfo current) => current.copyWith(
  branch: hasBranch ? branch : _kRoomInfoUnset,
  ctxPercent: hasCtxPercent ? ctxPercent : _kRoomInfoUnset,
  ctxMax: hasCtxMax ? ctxMax : _kRoomInfoUnset,
);
```

The typed app boundary preserves omitted telemetry and applies explicit null clears through the sentinel-backed `RoomInfo.copyWith`; `ConnectionManager` consumes this one projection rather than re-enumerating fields.

## Common violations

- Applying `patch.field ?? current.field` when explicit `null` must clear a nullable field.
- Treating `false` as absence or using `field || current` for patch application.
- Replacing cached local names or legacy metadata with every partial relay announcement.
- Applying partial-patch preservation rules to an authoritative snapshot and retaining state that the snapshot intentionally removed.

## Related

- `era-aware-authority-fallback-binding.md` — binds unmatched legacy facts only after durable authority is established.
- `edge-triggered-convergence.md` — suppresses publication after the merged semantic projection is unchanged.

# Presence-Aware Patch Merging

## Rationale

Incremental metadata updates must distinguish an omitted field from an explicit value. A patch representation carries field presence separately from the field value, so consumers preserve cached state when a producer sends a partial update while still applying explicit `false`, `null`, or replacement values according to the field contract. The same rule keeps relay state, app room caches, and compatibility metadata convergent across mixed versions.

## When to use

Use for partial room/session metadata, persisted record updates, and other merge-style updates:

1. Represent presence independently when `null` is itself meaningful (for example `Option<Option<T>>`, a presence flag, or a sentinel).
2. Preserve the cached field when the patch omits it.
3. Apply explicit values, including `false` and explicit clears, rather than using truthiness or a null-coalescing default that loses intent.
4. Make full snapshots authoritative when their contract differs from incremental patches, and test both forms.

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

## Common violations

- Applying `patch.field ?? current.field` when explicit `null` must clear a nullable field.
- Treating `false` as absence or using `field || current` for patch application.
- Replacing cached local names or legacy metadata with every partial relay announcement.
- Applying partial-patch preservation rules to an authoritative snapshot and retaining state that the snapshot intentionally removed.

## Related

- `era-aware-authority-fallback-binding.md` — binds unmatched legacy facts only after durable authority is established.
- `edge-triggered-convergence.md` — suppresses publication after the merged semantic projection is unchanged.

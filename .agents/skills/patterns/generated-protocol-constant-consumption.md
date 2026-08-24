# Pattern: Generated Protocol Constant Consumption

## Rationale

Wire message sets and resource limits are protocol facts, not local implementation knobs. Define them in the canonical schema and consume the generated constants, registries, and discriminators at every language boundary. Local modules may expose a narrow facade or derive a runtime helper, but they must not copy the literal value or hand-maintain a parallel allowlist.

## When to use

Use whenever a consumer needs a protocol message type, discriminator, field ceiling, frame budget, or upload limit:

- import the generated artifact directly or through a thin public protocol facade;
- derive unions, sets, validators, or local aliases from generated values;
- keep tests pointed at the same generated registry when checking coverage.

## When not to use

Do not put purely local UI thresholds, retry policy, or algorithm constants in the protocol schema. Do not regenerate or hand-edit generated outputs in a consumer module; change the schema/code generator instead.

## Examples

### Example 1: App upload code consumes generated limits through the facade

**File:** `app/lib/data/debug/debug_capture_uploader.dart:42-88`

```dart
if (bytes.length > captureUploadMaxTotalBytes) {
  throw const DebugCaptureUploadFailure(
    'too_large',
    'Debug logs exceed the 2 MiB delivery limit. Clear the log and retry.',
  );
}

while (sent < bytes.length) {
  final end = math.min(sent + captureUploadMaxChunkBytes, bytes.length);
  final chunk = bytes.sublist(sent, end);
  // Send the generated CaptureUploadChunk DTO.
}
```

`app/lib/protocol/protocol.dart` exports the generated Dart contract, so the app does not own another copy of the upload ceilings.

### Example 2: Extension validation uses generated type registries

**File:** `pi-extension/src/protocol/codec.ts:1-55`

```ts
import {
  CLIENT_MESSAGE_TYPES,
  SERVER_MESSAGE_TYPES,
  isClientMessage,
  isServerMessage,
} from "./generated/protocol.generated.js";

if (!SERVER_MESSAGE_TYPES.includes(type as ServerMessage["type"])) {
  throw new DecodeError("unsupported_type", `unknown type: ${type}`);
}
if (!isServerMessage(obj)) {
  throw new DecodeError("invalid_message", `invalid server message: ${type}`);
}
```

The decoder's allowlist and shape guard are inferred from generated protocol output rather than re-enumerated in the transport adapter.

### Example 3: Session scoping derives its sets from generated message types

**File:** `pi-extension/src/protocol/session_scope.ts:1-25`

```ts
import {
  SERVER_MESSAGE_TYPES,
  SESSION_SCOPED_CLIENT_MESSAGE_TYPES,
  SESSION_SCOPED_SERVER_MESSAGE_TYPES,
} from "./generated/protocol.generated.js";

export const SESSION_SCOPED_SERVER_TYPES = SESSION_SCOPED_SERVER_MESSAGE_TYPES;
export const SESSION_SCOPED_CLIENT_TYPES = SESSION_SCOPED_CLIENT_MESSAGE_TYPES;

export const NON_SESSION_SCOPED_SERVER_TYPES = SERVER_MESSAGE_TYPES.filter(
  (type) => !sessionScopedServerTypes.has(type),
);
```

Adding a schema message updates the generated registry and the derived session classification together.

### Example 4: Relay auth imports generated field ceilings

**File:** `relay/src/auth/challenge.rs:8-11,92-110,184-188`

```rust
use crate::protocol::generated::limits::{
    RELAY_MAX_CWD_BYTES, RELAY_MAX_DEVICE_ID_BYTES, RELAY_MAX_MODEL_BYTES,
    RELAY_MAX_PRE_AUTH_FRAME_BYTES, RELAY_MAX_ROOM_ID_BYTES, RELAY_MAX_ROOM_NAME_BYTES,
    RELAY_MAX_SESSION_ID_BYTES, RELAY_MAX_THINKING_BYTES,
};

ensure_field_size("device_id", &device_id, RELAY_MAX_DEVICE_ID_BYTES)?;
ensure_field_size("room_id", &room_id, RELAY_MAX_ROOM_ID_BYTES)?;
ensure_optional_field_size("room_meta.cwd", &meta.cwd, RELAY_MAX_CWD_BYTES)?;
if line.len() > RELAY_MAX_PRE_AUTH_FRAME_BYTES {
    return Err(AuthError::FrameTooLarge {
        actual: line.len(),
        max: RELAY_MAX_PRE_AUTH_FRAME_BYTES,
    });
}
```

The Rust boundary enforces the same schema-derived ceilings as the app and extension without copying their numeric literals.

## Common violations

- Repeating `8192`, `2097152`, or a message-type string in a consumer instead of importing the generated symbol.
- Maintaining a validator allowlist separately from the generated union/registry.
- Re-exporting a local constant with a changed value that silently widens or narrows the wire contract.
- Treating generated output as editable source rather than changing the canonical schema or generator.

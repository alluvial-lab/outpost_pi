# Closed-Category Content-Free Diagnostics

Represent boundary failures with closed reason categories and bounded numeric metadata, never raw payloads or attacker-controlled exception text.

## Rationale

Relay frames, encrypted owner traffic, and provider errors can contain prompts, ciphertext, tokens, or message bodies. App, extension, and relay boundaries independently project failures into stable categories before logging, preserving operational value without retaining content.

## Examples

### Example 1: Dart relay decoder returns only a reason and observed size
**File**: `app/lib/data/transport/relay_frame_decoder.dart:6-32`
```dart
enum RelayFrameDecodeFailure { tooLarge, malformed, unsupportedType }

final class RejectedRelayFrame extends RelayFrameDecodeResult {
  final RelayFrameDecodeFailure reason;
  final int observedSize;

  const RejectedRelayFrame({required this.reason, required this.observedSize});
}
```

### Example 2: TypeScript relay ingress exposes a closed error code
**File**: `pi-extension/src/protocol/relay_ingress.ts:43-51`
```ts
export class RelayIngressDecodeError extends Error {
  constructor(
    public readonly code: "too_large" | "invalid_message" | "unsupported_type",
    public readonly observedBytes: number,
  ) {
    super(`relay ingress rejected: ${code} (${observedBytes} bytes)`);
    this.name = "RelayIngressDecodeError";
  }
}
```

### Example 3: Rust relay logs the projected category, not the decoder error
**File**: `relay/src/handlers/peer.rs:214-224`
```rust
let frame = match decode_relay_frame(&text) {
    Ok(frame) => frame,
    Err(err) => {
        if invalid_frame_logs_remaining > 0 {
            invalid_frame_logs_remaining -= 1;
            warn!(
                peer = %peer_short,
                category = err.category(),
                frame_bytes = text.len(),
                "invalid relay frame, dropping"
            );
        }
        continue;
    }
};
```

## When to Use
- At wire, crypto, provider, subprocess, and persistence boundaries where raw errors may contain sensitive input.
- For persistent diagnostics or logs exported to users and CI.

## When NOT to Use
- For internal programming errors whose full stack is confined to a controlled development-only sink.
- When a typed domain error is already guaranteed to contain no untrusted text.

## Common Violations
- Logging `error.toString()` from a decoder, provider, or transport.
- Storing ciphertext, raw JSON, message previews, or arbitrary server error text alongside a safe category.
- Accepting free-form diagnostic reason strings where a closed enum/union is available.

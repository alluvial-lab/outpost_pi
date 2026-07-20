---
kind: story
release_binding: relay-0.2.0
parent: feature-typed-bounded-relay-decoding
stage: done
id: gate-security-preauth-websocket-size-limits
tags: [security, relay]
depends_on: []
gate_origin: security
created: 2026-07-12
updated: 2026-07-19
---

# Pre-auth WebSocket frames and hello metadata lack explicit size limits

## Severity
Medium

## Domain
Input Validation & Injection / API Security

## Location
`relay/src/handlers/peer.rs:33`

## Evidence
```rust
pub async fn ws_handler(
    ws: WebSocketUpgrade,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    State(state): State<AppState>,
) -> Response {
    ws.on_upgrade(move |socket| handle_peer(socket, addr, state))
}
```

## Remediation direction
Configure explicit WebSocket frame/message ceilings before upgrade and add bounded lengths for pre-auth `device_id`, `room_id`, and room-metadata strings in the canonical schema plus the Rust parse boundary. Reject oversized hello/auth frames before retaining or logging their fields, and cover the limits with unauthenticated resource-exhaustion tests.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected for security-critical relay work).
- Review weight: `standard` (caller default; feature-level review only).
- Files changed: `relay/src/auth/challenge.rs`, `relay/src/handlers/peer.rs`, `relay/src/resource_limits.rs`, `relay/src/lib.rs`, `relay/Cargo.toml`, `relay/src/auth/auth_test.rs`, `relay/tests/integration.rs`.
- Tests added: pre-parse frame rejection, UTF-8 metadata-byte limits, deterministic fixed-window support tests, and an unauthenticated WebSocket oversize-close regression.
- Simplification: relay policy constants now share one resource-limit module; Axum frame and reassembled-message ceilings derive from the configured decoded payload ceiling.
- Discrepancies from design: schema/codegen and endpoint projections are outside this relay-only worker's allowed write scope; the relay boundary enforces the designed values locally, and the remaining cross-stack stories are explicitly left for their owning workers.
- Adjacent issues parked: none.
- Verification: focused auth, resource-policy, protocol-frame, and WebSocket integration tests passed.

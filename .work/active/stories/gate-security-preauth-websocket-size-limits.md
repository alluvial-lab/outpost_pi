---
kind: story
release_binding: null
parent: feature-typed-bounded-relay-decoding
stage: drafting
id: gate-security-preauth-websocket-size-limits
tags: [security, relay]
depends_on: []
gate_origin: security
created: 2026-07-12
updated: 2026-07-12
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

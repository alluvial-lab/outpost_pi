---
id: gate-security-preauth-large-message-allocation
kind: story
stage: implementing
tags: [security, relay]
parent: null
depends_on: []
release_binding: relay-0.2.0
gate_origin: security
created: 2026-07-20
updated: 2026-07-19
---

# Pre-auth sockets can allocate the full authenticated message ceiling

## Severity
High

## Domain
API Security / Input Validation & Injection

## Location
`relay/src/handlers/peer.rs:28`

## Evidence
```rust
ws.max_frame_size(max_ws_message_bytes())
    .max_message_size(max_ws_message_bytes())
    .on_upgrade(move |socket| handle_peer(socket, addr, state))
```

## Remediation direction
Enforce the 16 KiB pre-auth ceiling before Tungstenite allocates a complete
message, while preserving the larger post-auth data-plane ceiling. If the
WebSocket stack cannot change limits after authentication, add a pre-auth
transport/admission boundary (including concurrent-handshake limits) that
prevents many unauthenticated sockets from each allocating the configured
5.6 MiB default message maximum. Keep the existing parser-level field checks as
defense in depth, not as the allocation boundary.

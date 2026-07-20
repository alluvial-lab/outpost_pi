---
id: gate-security-preauth-large-message-allocation
kind: story
stage: done
tags: [security, relay]
parent: null
depends_on: []
release_binding: relay-0.2.0
gate_origin: security
created: 2026-07-20
updated: 2026-07-20
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

## Implementation notes

**Execution capability:** inline fix (orchestrator-rescued). The initial
parallel sub-agent dispatch made the code edits but could not verify due to
cargo file-lock contention across four concurrent relay builds; the
orchestrator completed verification serially.

**Root cause:** `ws_handler` configured the WebSocket upgrade with the
authenticated data-plane ceiling (`max_ws_message_bytes()`, ~5.6 MiB) for
*all* sockets, including unauthenticated ones. Tungstenite would therefore
allocate/reassemble a complete multi-megabyte message from an unauthenticated
peer before any auth check ran. The parser-level field checks were
defense-in-depth, not the allocation boundary.

**Fix approach:** Wrap the upgraded transport in a `PreAuthGuard<S>` that
inspects incoming bytes before Tungstenite reassembles. While the connection
is unauthenticated (`AtomicBool` flipped true only after `verify_auth`
succeeds), the guard tracks cumulative message bytes per WebSocket message
and rejects with an I/O error once they exceed `PRE_AUTH_MESSAGE_MAX_BYTES`
(16 KiB, from `RELAY_MAX_PRE_AUTH_FRAME_BYTES`). After auth, the guard is a
pass-through and the socket retains the full authenticated ceiling. The
relay moved from axum's `WebSocketUpgrade` to a raw `tokio-tungstenite`
handshake (`create_response_with_body` + `WebSocketStream::from_raw_socket`)
so the `WebSocketConfig` and the custom transport guard could be composed;
`tokio-tungstenite` was promoted from dev-dependency to dependency.

**Files changed:**
- `relay/src/handlers/peer.rs` — `PreAuthGuard` transport wrapper, raw
  tungstenite handshake, type conversions (axum `Message` ↔ tungstenite
  `Message`).
- `relay/src/resource_limits.rs` — `PRE_AUTH_MESSAGE_MAX_BYTES` const.
- `relay/Cargo.toml` / `Cargo.lock` — `tokio-tungstenite` promoted to
  `[dependencies]`; `hyper` + `hyper-util` added for the upgrade plumbing.
- `relay/tests/integration.rs` — regression test
  `fragmented_oversized_hello_is_rejected_from_header_before_final_payload`.

**Regression test:** `relay/tests/integration.rs` —
`fragmented_oversized_hello_is_rejected_from_header_before_final_payload`
sends a fragmented WebSocket text message whose total exceeds
`PRE_AUTH_MESSAGE_MAX_BYTES` *before* authenticating, and asserts the socket
closes before the complete text reaches the auth parser. Proves the
allocation boundary, not just post-parse rejection.

**Four-step confirmation:**
1. New test passes (proves the transport rejects oversized pre-auth frames).
2. Full suite: 219 passed, 0 failed (158 unit + 61 integration).
3. `cargo fmt --check` clean; `cargo clippy --all-targets -- -D warnings` clean.
4. Symptom resolved: unauthenticated sockets can no longer allocate beyond
   the 16 KiB pre-auth ceiling; authenticated sockets retain the 5.6 MiB
   data-plane ceiling.

**Parked for separate consideration:** none.

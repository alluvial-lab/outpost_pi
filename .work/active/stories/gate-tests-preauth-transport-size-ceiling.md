---
id: gate-tests-preauth-transport-size-ceiling
kind: story
stage: review
tags: [testing, relay]
parent: null
depends_on: [gate-security-preauth-large-message-allocation]
release_binding: relay-0.2.0
gate_origin: tests
created: 2026-07-20
updated: 2026-07-20
---

# Prove the pre-auth size ceiling at the WebSocket transport boundary

## Priority
High

## Value evidence
Item: `gate-security-preauth-websocket-size-limits`

Contract / risk / regression / maintenance cost: the security item requires oversized unauthenticated frames to be rejected before retention or parsing, but `relay/tests/integration.rs:120-128` sends only 16 KiB + 1 and treats any eventual close as success. The upgrade still configures Tungstenite with the authenticated data-plane ceiling at `relay/src/handlers/peer.rs:28-29` (5,657,944 bytes under the default policy), so this test passes even while an unauthenticated socket may allocate a complete multi-megabyte message. The underlying production defect is already tracked by release-blocking item `gate-security-preauth-large-message-allocation`; this regression test is needed to prove that fix closes the allocation boundary rather than only rejecting after allocation.

## Gap type
important-interface / bug-regression — the current integration assertion proves handler-level rejection, not the consequential transport allocation ceiling.

## Suggested test
```rust
#[tokio::test]
async fn preauth_transport_never_reassembles_beyond_pre_auth_limit() {
    // Connect without authenticating and send a fragmented text message whose
    // total size exceeds RELAY_MAX_PRE_AUTH_FRAME_BYTES.
    // Assert the transport closes before the complete text reaches the auth
    // parser/handshake owner; then prove a fully authenticated connection can
    // still use the larger data-plane ceiling.
}
```

## Test location (suggested)
`relay/tests/integration.rs`

## Implementation notes

- The dependency fix's existing `fragmented_oversized_hello_is_rejected_from_header_before_final_payload` regression already proves the allocation-boundary half: it sends the final continuation-frame header while withholding its payload, so Tungstenite cannot produce complete text for the auth parser before the transport rejects the cumulative declared size.
- That test did not prove the second required half. Added `authenticated_connection_routes_message_above_pre_auth_ceiling`, which fully authenticates two peers, sends and routes a valid outer envelope larger than `PRE_AUTH_MESSAGE_MAX_BYTES`, and verifies the ciphertext reaches the recipient unchanged.
- Verification passed from `relay/`: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` (220 tests, 0 failed).

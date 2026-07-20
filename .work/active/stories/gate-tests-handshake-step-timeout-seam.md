---
id: gate-tests-handshake-step-timeout-seam
kind: story
stage: implementing
tags: [testing, relay]
parent: null
depends_on: [gate-security-preauth-large-message-allocation]
release_binding: relay-0.2.0
gate_origin: tests
created: 2026-07-20
updated: 2026-07-19
---

# Cover both handshake timeout phases through the live WebSocket seam

## Priority
High

## Value evidence
Item: `feature-relay-resource-bounds`

Contract / risk / regression / maintenance cost: this feature closes the known unauthenticated socket/task retention vector by applying an independent five-second deadline to both hello and auth. The only timeout test exercises the private generic helper with one pending stream at `relay/src/handlers/peer.rs:247-251`; it does not prove `handle_peer` wires that helper into both waits at `relay/src/handlers/peer.rs:41` and `relay/src/handlers/peer.rs:72`, closes each stalled socket, or avoids registry admission. `relay/tests/integration.rs:68-111` covers invalid signatures, but no live-socket test covers either timeout phase. A future wiring regression could therefore restore the release's original DoS while the helper test stays green.

## Gap type
important-interface / bug-regression — missing state-transition coverage for pre-hello and post-challenge stalls at the public WebSocket boundary.

## Suggested test
```rust
#[tokio::test(start_paused = true)]
async fn each_stalled_handshake_phase_closes_without_registration() {
    // Scenario 1: connect and send no hello; advance the handshake deadline.
    // Scenario 2: send a valid hello, receive challenge, then send no auth;
    // advance the independent deadline.
    // In both cases assert the socket closes and the peer/room was never
    // admitted to the registry. Use injected state/deadline if the live server
    // cannot share paused Tokio time deterministically.
}
```

## Test location (suggested)
`relay/tests/integration.rs`

---
id: feature-cruft-consolidated-cleanup-step-2-relay
kind: story
stage: done
tags: [refactor, cleanup, relay]
parent: feature-cruft-consolidated-cleanup
depends_on: [feature-cruft-consolidated-cleanup-step-1-app]
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Consolidated cruft cleanup: relay

## Scope

Implement the verified relay-side cleanup findings from
`feature-cruft-consolidated-cleanup`. Keep the production bounded mailbox,
room-targeted forwarding, auth behavior, and all protocol shapes unchanged.

## Current state

`relay/src/lib.rs:13-22` exposes a test-only compatibility module that calls a
bounded channel an unbounded channel and aliases its receiver:

```rust
pub(crate) mod bounded_mpsc {
    pub(crate) use tokio::sync::mpsc::Receiver as UnboundedReceiver;

    pub(crate) fn unbounded_channel<T>()
    -> (tokio::sync::mpsc::Sender<T>, tokio::sync::mpsc::Receiver<T>) {
        tokio::sync::mpsc::channel(crate::resource_limits::OUTBOUND_QUEUE_CAPACITY)
    }
}
```

`relay/src/peers/registry.rs:75-96` retains a single-implementation
`PresenceTransitions` trait whose methods delegate directly to inherent
`PresenceState` methods. Test callers still use the misleading
`mpsc::unbounded_channel` name through that module.

`relay/src/handlers/pi_forward.rs:18-21` still says cross-PC forwarding is
"peer-wide in this slice", although the implementation at
`:365-373` calls `send_to_room` and the current protocol requires a non-empty
`to_room`. The `AppState.mesh_auth` comment in `relay/src/lib.rs` is already a
current-state contract and needs no edit.

`relay/src/auth/challenge.rs:67-69` still has the test-only `parse_hello`
pass-through; its only remaining in-repository caller is
`relay/src/auth/auth_test.rs:45`. Production admission already calls
`parse_hello_bootstrap`.

## Target state

- Delete the `test_support::bounded_mpsc` compatibility module. In the relay
  test modules that used it, import `tokio::sync::mpsc` and construct
  `mpsc::channel::<Message>(OUTBOUND_QUEUE_CAPACITY)` directly. Use
  `mpsc::Receiver<Message>` in helper signatures. This keeps the same capacity
  from `resource_limits::OUTBOUND_QUEUE_CAPACITY` and preserves bounded
  backpressure in all fixtures.
- Delete `PresenceTransitions` and its impl. Leave the existing calls on
  `PresenceState`; inherent methods with the same behavior remain the direct
  owner of the transition logic.
- Rewrite the `pi_forward.rs` module contract to state that `to_room` targets
  one destination room, the sender connection is skipped, and envelope/body
  content remains opaque. Remove the stale "peer-wide"/"this slice" wording.
- Update the auth test to call `parse_hello_bootstrap(&line, 0)` and remove
  `parse_hello`. This is an internal relay-library symbol with no published
  external consumer; the in-repository migration is the compatibility path.

## Explicit exclusions

- Do not touch the four boolean-equality assertions: the current tree already
  uses `assert!`/`assert!(!...)`; the v0.4.0 finding is complete.
- Do not remove `ActorDispatch::Close`: current production rate-limit admission
  constructs it in `dispatch_pi_envelope`, and `peer.rs` handles it by closing
  the loop. Removing it would change behavior.

## Acceptance criteria

- [x] No relay test uses the `unbounded_channel` name or
      `UnboundedReceiver` alias; every fixture channel uses the shared bounded
      capacity constant.
- [x] Presence behavior tests remain unchanged in meaning and continue to
      cover online/offline transitions.
- [x] The module comment describes room-targeted forwarding and opaque payloads;
      it does not claim peer-wide delivery.
- [x] `parse_hello` has no declaration or import and auth tests still assert the
      same `AuthError::NoHello` result through `parse_hello_bootstrap`.
- [x] `cargo fmt --check` passes.
- [x] `cargo clippy -- -D warnings` passes.
- [x] `cargo test` passes.
- [x] No relay production mailbox capacity, routing, or wire frame changes are
      included.

## Implementation

Removed the test-only bounded-channel compatibility facade and migrated all
relay fixtures to `tokio::sync::mpsc::channel` with the shared
`OUTBOUND_QUEUE_CAPACITY` (16-frame) limit. This preserves the bounded mailbox
model while making fixture types and names accurate. Removed the one-implementation
`PresenceTransitions` pass-through and call the unit `PresenceState` transition
functions directly; the `PeerRegistry` keeps the same transition ordering and
publication behavior. Corrected the Pi-forward module contract to describe
room-targeted delivery, sender skipping, and opaque endpoint data. Removed the
internal `parse_hello` test wrapper and migrated its sole test caller to
`parse_hello_bootstrap(line, 0)` without changing the `AuthError::NoHello`
assertion. `ActorDispatch::Close`, boolean assertions, and the current mesh-auth
comment were intentionally left untouched.

Verification: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo
test` passed. The relay suite reported 170 unit tests plus all integration,
mesh, Pi-forward, presence, protocol-parity, and rooms tests green.

## Risk

Low. The channel rename touches several test modules, so an omitted receiver
signature or capacity argument is possible, but the compiler and full relay
suite expose it. Removing `parse_hello` removes an internal source symbol, not
wire behavior; all known callers have an explicit migration.

## Rollback

Revert the relay cleanup commit. Restoring the test-only shim, trait wrapper,
comment, and parser wrapper does not alter relay state or persisted mesh data.

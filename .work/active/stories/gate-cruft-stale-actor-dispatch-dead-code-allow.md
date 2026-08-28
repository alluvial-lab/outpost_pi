---
id: gate-cruft-stale-actor-dispatch-dead-code-allow
kind: story
stage: implementing
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.11.0
gate_origin: cruft
created: 2026-08-28
updated: 2026-08-28
---

# Remove the stale dead-code allowance from ActorDispatch::Close

## Confidence
High

## Category
dead code / stale compiler suppression

## Location
`relay/src/handlers/connection_actor.rs:107-110`

## Evidence
```rust
pub(crate) enum ActorDispatch {
    Continue,
    #[allow(dead_code)]
    Close,
```

`ActorDispatch::Close` is constructed by `dispatch_pi_envelope` at
`relay/src/handlers/connection_actor.rs:250` and consumed by the production
peer loop at `relay/src/handlers/peer.rs:227`. The allowance is therefore a
stale suppression rather than protection for an unused variant.

## Removal
Delete the `#[allow(dead_code)]` attribute. Keep the `Close` variant and its
peer-loop handling; no runtime behavior or connection-close guarantee changes.

---
id: gate-security-relay-room-discovery-authorization
kind: story
tags: [relay, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-08-28
updated: 2026-08-28
---

# Relay room discovery exposes metadata to unrelated authenticated peers

## Severity
Medium

## Domain
Authentication & Authorization

## Location
`relay/src/handlers/control.rs:148`

## Evidence
```rust
let Some(peers) = self.bounded_peers(frame_type, peers) else {
    return ActorDispatch::Continue;
};
self.actor.rooms.subscribe(self.actor.peer_id.clone(), peers).await;
```

The boundary validates only that each requested peer id is canonical. It never checks that the authenticated subscriber is the Owner of, or a signed-mesh sibling of, the requested peer. The adjacent `rooms_check` path likewise returns snapshots for any canonical peer id (`relay/src/handlers/control.rs:178-185`). An unrelated relay client that knows a target public key can therefore obtain room name, cwd, session id, model, thinking level, working state, and the new background-work state. Self-hosted deployment narrows exposure but does not establish this authorization relationship.

## Remediation direction
Authorize presence/room subscription and check targets against verified Owner/mesh relationships before storing subscriptions or returning snapshots. Permit the Owner key and signed sibling Pis explicitly, reject unrelated peers without target-state disclosure, invalidate subscriptions when membership changes, and add negative tests using independently authenticated keys.

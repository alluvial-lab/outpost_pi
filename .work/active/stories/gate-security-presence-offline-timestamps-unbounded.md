---
id: gate-security-presence-offline-timestamps-unbounded
kind: story
stage: done
tags: [relay, security]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: security
created: 2026-07-19
updated: 2026-08-11
---

# Presence offline timestamps retain attacker-created peer identities forever

## Source

Parked from the `standard`-weight cross-model review of
`feature-relay-resource-bounds` (2026-07-19). Lower-risk finding — adjacent
retained-state risk, predates the reviewed commits.

## Finding

`relay/src/presence.rs` (lines ~13, 83-88): `last_offline_ts` has no expiry or
bound. An authenticated-key churn attack (creating many distinct peer
identities that go offline) can grow this map indefinitely.

## Risk rationale (why parked, not fixed this cycle)

Predates the `feature-relay-resource-bounds` commits; each entry is small (a
peer_id → timestamp mapping). The feature's scope was the four named
resource-bounds (auth timeout, envelope-auth scan, subscription retention,
outbound queues), not the presence offline-timestamp map. It is adjacent
retained-state risk of the same DoS class.

## Recommended direction

Add an expiry/retention bound to `last_offline_ts` (evict entries older than a
retention window, or cap the map size with LRU eviction) consistent with the
subscription-target retention bound the feature already added.

## Implementation notes
- Added the shared `MAX_PRESENCE_OFFLINE_TIMESTAMPS` bound (1,024) and evicts the oldest timestamp before admitting a new peer at capacity.
- Added `presence::tests::offline_timestamp_retention_evicts_oldest_peer_at_capacity`.
- Verification: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` (159 unit tests plus all integration suites) passed from `relay/`.
- Parked issues: none.

---
id: gate-tests-mesh-auth-cache-ttl
kind: story
stage: done
tags: [testing, relay]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: tests
created: 2026-07-20
updated: 2026-08-11
---

# Cover mesh-authorization cache expiry and refresh

## Priority
Medium

## Value evidence
Item: `feature-relay-resource-bounds`

Contract / risk / regression / maintenance cost: the resource-bound contract says positive and negative mesh-membership entries remain authoritative for 60 seconds and then refresh. Production expiry and purge logic lives at `relay/src/handlers/pi_forward.rs:115-123` and `relay/src/handlers/pi_forward.rs:144-166`. Existing cache tests cover hits, capacity, same-key concurrency, publish invalidation, and publish/scan races (`relay/src/handlers/pi_forward.rs:646-804`), but none crosses the TTL. A comparison or timestamp regression could leave stale authorization results retained indefinitely while the stronger concurrency/capacity suite stays green.

## Gap type
complex-unit / boundary — missing deterministic coverage immediately before and at the cache TTL, for both found and absent entries.

## Suggested test
```rust
#[test]
fn positive_and_negative_membership_refresh_at_ttl() {
    // Inject a monotonic clock into MeshAuthCache.
    // Verify each entry is reused immediately before MESH_AUTH_CACHE_TTL,
    // then advance exactly to the TTL and assert one fresh store scan occurs,
    // the stale entry is replaced, and the cache remains within capacity.
}
```

## Test location (suggested)
`relay/src/handlers/pi_forward.rs`

## Implementation notes
- Added a test-only monotonic-clock seam to `MeshAuthCache`, keeping production time sourced from `Instant::now()`.
- Added `positive_and_negative_membership_refresh_at_ttl`: both result types are reused one nanosecond before the 60-second TTL and rescanned/replaced at the exact TTL boundary; it also confirms the capacity invariant.
- Verification: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` passed from `relay/` (161 unit tests plus all integration suites).
- Parked issues: none.

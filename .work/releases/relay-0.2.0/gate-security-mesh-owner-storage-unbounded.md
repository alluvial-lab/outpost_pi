---
id: gate-security-mesh-owner-storage-unbounded
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

# Public mesh publishes can create unbounded persistent Owner records

## Severity
High

## Domain
API Security / Infrastructure & Deployment

## Location
`relay/src/mesh/handler.rs:98`

## Evidence
```rust
match state.mesh.upsert(
    &computed_hash,
    &owner_pk_bytes,
    header.version,
    &env.blob,
```

## Remediation direction
Add admission and storage quotas around mesh publication: bound total retained
rows/bytes, rate-limit creation of new Owner hashes, and define safe eviction or
operator rejection behavior before disk pressure. A valid self-signature proves
control of a newly generated Owner key but does not make an Internet client
entitled to unlimited relay storage; the 500 KiB per-request body cap therefore
needs a process/deployment-wide retained-state bound.

## Root cause

`MeshStore::upsert` enforced only per-Owner monotonic versions, so every valid
self-signed, previously unseen Owner hash created another persistent SQLite row
without any deployment-wide row, byte, or creation-rate admission limit.

## Fix approach

Keep the policy values in `relay/src/resource_limits.rs` and enforce them
atomically with the SQLite upsert: retain at most 1,024 Owner rows and 64 MiB of
variable-field data, and admit at most 32 new Owner hashes per process every 60
seconds. Existing Owner updates do not consume the creation budget. The relay
rejects storage-cap growth with HTTP 507 `mesh_storage_quota_exceeded` and
creation-rate overflow with HTTP 429 `new_owner_rate_limited`; it does not evict
Owners implicitly because that would revoke live mesh authorization.

## Regression test

`relay/src/mesh/store.rs::upsert_bounds_distinct_owner_rows` inserts distinct
Owner hashes through the store up to the configured row ceiling, asserts the
next insert returns the `owner_rows` quota error, and asserts retained row count
stays at the ceiling. Additional store tests cover the retained-byte ceiling and
new-Owner window rollover. `relay/tests/mesh_test.rs::post_rate_limits_new_owner_creation_process_wide`
publishes valid signed envelopes for distinct Owner keys through the HTTP API
and asserts the excess publish returns HTTP 429 with `new_owner_rate_limited`.

## Implementation notes

- Execution capability: direct inline implementation; this is a focused
  relay-local persistence/admission fix with one storage owner and one HTTP
  adapter, so delegation would add handoff cost without improving isolation.
- Files changed: `relay/src/resource_limits.rs`, `relay/src/mesh/store.rs`,
  `relay/src/mesh/handler.rs`, `relay/tests/mesh_test.rs`, and `PROTOCOL.md`.
- Reproduction: before enforcement, the new row-bound regression failed with
  `a new Owner beyond the row quota was stored` after the store accepted the
  1,025th distinct hash.
- Verification so far: in an isolated clean detached worktree containing these
  changes, rustfmt check passed for all changed Rust files; all seven mesh-store
  unit tests passed; the exact row-bound regression passed; and the exact HTTP
  new-Owner rate-limit integration test passed.
- Blocked verification: the required shared-checkout
  `cargo fmt --check && cargo clippy -- -D warnings && cargo test` serial pass
  was not completed because parallel relay work held/changed the shared Cargo
  build surface. Per operator instruction, no further Cargo command or commit
  was attempted. The story remains `stage: implementing` pending orchestrator
  verification and commit.
- Adjacent issues parked: none.

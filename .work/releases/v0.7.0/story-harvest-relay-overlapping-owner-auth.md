---
id: story-harvest-relay-overlapping-owner-auth
kind: story
stage: done
tags: [relay, security, bug]
parent: feature-upstream-remote-pi-harvest
depends_on: []
release_binding: v0.7.0
gate_origin: null
created: 2026-08-15
updated: 2026-08-16
---

# Overlapping-owner mesh authorization is order-dependent (first match wins)

Upstream `e7aed39b`: when a Pi participates in meshes owned by MORE than one
Owner, authorization must consider the UNION of every matching owner, not the
first row SQLite yields. Our `relay/src/handlers/pi_forward.rs:226-255`
iterates stored owner envelopes and returns on the first match — whether an
overlapping owner authorizes the Pi depends on iteration order (a denial or
grant can flip on row order). We are not aware of a live overlapping-owner
deployment today, which is why this hasn't bitten; it is a correctness bug in
the authorization path and cheap to fix before the mesh grows.

## Direction

Port the union semantics (upstream `pi_forward.rs:77-95`): collect all
matching owner authorizations before deciding; a Pi is authorized if ANY
contributing owner mesh admits it. The mesh-authorization cache must then
track ALL contributing owner hashes for invalidation (an eviction keyed to
one owner must not leave a stale "authorized" verdict sourced from a
revoked mesh) — see the identity-scoped-monotonic-high-watermarks and
stale-capability-eviction patterns for the invalidation discipline.
Property test: two owners, one authorizing; assert order-independence under
shuffled insertion.

## Verification

`cargo fmt --check && cargo clippy -- -D warnings && cargo test`. Cite
upstream sha in the commit message.

## Implementation

- Ported upstream `e7aed39b` as union authorization in
  `relay/src/handlers/pi_forward.rs`: a cold scan now collects every verified
  Owner mesh containing the source Pi and authorizes against their combined
  members instead of returning the first SQLite match.
- Cached positive memberships now retain every contributing Owner hash.
  Owner-publish invalidation evicts an aggregate verdict when any contributing
  Owner changes, including full source-Pi revocation from that Owner's new blob.
- Added deterministic shuffled-insertion coverage for two overlapping Owners
  with one authorizing mesh, plus a regression test proving authorizing-Owner
  revocation invalidates the cached union.
- Verification: `cd relay && cargo fmt --check && cargo clippy -- -D warnings &&
  cargo test` passed (170 unit tests and 64 integration tests; 0 failures).
- Execution capability: sol/high, selected for authorization-path semantics and
  cache invalidation discipline. Review: not applicable for this child-story
  checkpoint. Deviations and parked findings: none.

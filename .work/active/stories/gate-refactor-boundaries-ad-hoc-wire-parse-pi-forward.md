---
id: gate-refactor-boundaries-ad-hoc-wire-parse-pi-forward
kind: story
stage: done
tags: [relay]
parent: feature-boundary-typed-decoders
depends_on: []
release_binding: v0.4.0
gate_origin: refactor
created: 2026-07-12
updated: 2026-08-11
---

# Parse mesh-members blobs through a typed boundary DTO

## Library
boundaries

## Rule
ad-hoc-wire-parse

## Confidence
Medium

## Location
`relay/src/handlers/pi_forward.rs:97`

## Issue
`MeshAuthCache::members_of` deserializes a verified mesh envelope into `serde_json::Value` and navigates `members` and `remote_epk` with `.get()`; no generated DTO covers this inner blob.

## Fix
Design an authored or generated mesh-members DTO at the mesh-storage boundary, with deliberate malformed-member behavior, then pass the typed member identities into authorization. Do not claim an existing generated relay frame represents this interior blob.

## Consolidated from
`gate-refactor-boundaries-mesh-blob-adhoc-parse` (duplicate, archived 2026-07-15).
That item corroborated the same `MeshAuthCache::members_of` gap at
`pi_forward.rs:106` (this item cites `:97`) and noted the `.as_array()`
navigation; folded here. It had leaked into backlog as a malformed
`stage: drafting` item.

## Implementation notes

- Added strict Serde mesh-members DTOs and `decode_member_keys` at the mesh
  boundary; malformed member data rejects the full signed record.
- Authorization scans and publish invalidation consume only typed member keys;
  malformed publishes invalidate conservatively without granting membership.
- Verified with `cargo fmt --check`, `cargo clippy -- -D warnings`, and
  `cargo test` (166 unit, 64 integration, 0 doc tests).

---
id: gate-refactor-boundaries-ad-hoc-wire-parse-pi-forward
created: 2026-07-12
updated: 2026-07-12
tags: [relay]
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

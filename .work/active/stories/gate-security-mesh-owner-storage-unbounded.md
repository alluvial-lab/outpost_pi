---
id: gate-security-mesh-owner-storage-unbounded
kind: story
stage: implementing
tags: [security, relay]
parent: null
depends_on: []
release_binding: relay-0.2.0
gate_origin: security
created: 2026-07-20
updated: 2026-07-19
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

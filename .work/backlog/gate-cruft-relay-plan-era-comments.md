---
id: gate-cruft-relay-plan-era-comments
kind: story
stage: drafting
tags: [cleanup, relay]
parent: null
depends_on: []
release_binding: null
gate_origin: cruft
created: 2026-07-20
updated: 2026-07-19
---

# Rewrite plan-era relay comments as current-state contracts

## Severity
Low

## Confidence
Medium

## Category
stale comment

## Relevance
Release-relevant

## Decision required
no

## Location
`relay/src/lib.rs:51-53`; `relay/src/handlers/pi_forward.rs:1`

## Evidence
```rust
/// Plan 25 — caches `Pi-pubkey → mesh siblings` to avoid hitting SQLite
/// for every `pi_envelope` forward (60 s TTL).
pub mesh_auth: Arc<MeshAuthCache>,
```

```rust
//! Plan 25 Wave A — Pi-to-Pi envelope forwarding via the relay.
```

## Removal
Remove historical plan/wave labels and describe the current bounded positive/negative, single-flight mesh-authorization cache and cross-PC forwarding responsibility directly. Preserve the load-bearing TTL, authorization, invalidation, and payload-opacity facts without progress-era framing.

## Gate scan context
Scanner execution was inline at the operator's direction, with reduced isolation and no scanner sub-agent.

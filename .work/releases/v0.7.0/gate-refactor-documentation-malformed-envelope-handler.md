---
id: gate-refactor-documentation-malformed-envelope-handler
kind: story
stage: done
tags: [refactor]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: refactor
created: 2026-08-24
updated: 2026-08-25
---

# Document the relay malformed-envelope escape hatch

## Library
documentation

## Rule
shared-export

## Confidence
High

## Location
`relay/src/handlers/pi_forward.rs:404`

## Issue
The `pub(crate)` `handle_malformed_pi_envelope` boundary intentionally accepts `serde_json::Value` outside the generated typed path, but has no rustdoc explaining that exception or its deterministic `bad_envelope` transport-error behavior.

## Fix
Add `///` rustdoc that records the malformed-frame boundary purpose, the limited raw fields it reads, and the returned transport-error contract.

## Implementation
- Execution capability: `sol/high` (caller-selected; documentation-only Rust boundary fix).
- Added rustdoc identifying the raw malformed-envelope ingress exception, limiting its reads to optional inner `id`/`from` strings, and documenting deterministic correlated `bad_envelope` transport errors.
- Runtime behavior is unchanged; existing malformed-envelope unit and integration tests continue to cover the contract.
- Verification: `cargo fmt --check`, `cargo clippy -- -D warnings`, and all relay tests pass (170 unit plus integration suites).
- Adjacent issues parked: none.

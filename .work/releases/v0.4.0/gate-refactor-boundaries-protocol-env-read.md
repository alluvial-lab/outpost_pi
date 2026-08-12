---
id: gate-refactor-boundaries-protocol-env-read
kind: story
stage: done
tags: [relay]
parent: feature-boundary-typed-decoders
depends_on: []
release_binding: v0.4.0
gate_origin: refactor
created: 2026-07-01
updated: 2026-08-11
---

# relay/src/protocol/outer.rs:34

## Library
domains-imports-infra

## Rule
Medium

## Confidence
Protocol parser reads process environment directly

## Location
relay/src/protocol/outer.rs is an authored protocol module, but max_ct_bytes() reads std::env::var(MAX_CT_ENV) directly, coupling protocol parsing to process configuration instead of receiving a parsed limit from the relay composition/config boundary.

## Issue
needs analysis: move env parsing to the relay configuration/composition boundary and inject/pass the max ct byte limit into the parser.

## Fix

## Implementation notes

- Added `RelayConfig` as the sole `RELAY_MAX_CT_MIB` environment reader, with
  the prior default, trimming, positive-integer, and saturating-MiB policy.
- Added injected `OuterEnvelopeParser`; the same instance configures WebSocket
  admission and authenticated frame decoding through `AppState`.
- Verified with `cargo fmt --check`, `cargo clippy -- -D warnings`, and
  `cargo test` (168 unit, 64 integration, 0 doc tests).


---
id: gate-cruft-relay-test-bool-assertions
kind: story
stage: done
tags: [cleanup, relay]
parent: null
depends_on: []
release_binding: v0.4.0
gate_origin: cruft
created: 2026-07-20
updated: 2026-08-11
---

# Replace clippy-rejected boolean equality assertions in relay tests

## Severity
Low

## Confidence
High

## Category
low-value test syntax

## Relevance
Ambient

## Decision required
no

## Location
`relay/src/peers/registry.rs:1233,1248,1263,1294`

## Evidence
```rust
assert_eq!(rooms_snapshot[0].working, false);
assert_eq!(rooms_snapshot[0].working, true);
assert_eq!(rooms_snapshot[0].working, false);
assert_eq!(rooms_snapshot[0].working, true);
```

`cargo clippy --all-targets -- -D warnings` reports all four as `clippy::bool_assert_comparison` errors.

## Removal
Use `assert!` and `assert!(!...)` so all-target clippy remains useful and the tests express the boolean contract directly. These lines predate the release changes, so the finding is ambient and unbound.

## Gate scan context
Scanner execution was inline at the operator's direction, with reduced isolation and no scanner sub-agent.

## Implementation notes
- Inspected `relay/src/peers/registry.rs`: all four cited `working` assertions already use idiomatic `assert!` / `assert!(!...)`; no production or test change was necessary.
- Verification: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` (run from `relay/`) all passed, including the affected registry tests.
- Parked issues: none.

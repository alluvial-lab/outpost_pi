---
id: story-refresh-relay-rust-toolchain-dependencies
kind: story
stage: done
tags: [relay, deps]
parent: feature-stack-currency-review
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Relay: Rust toolchain pin + 75 compatible lock refresh + audit

Pin/minimum rustc policy, cargo update within constraints (75 compatible), cargo audit clean, fmt/clippy/test green.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

## Closure

- **Toolchain policy:** `relay/Cargo.toml` now declares Rust `1.94` as the
  minimum supported version, and `relay/rust-toolchain.toml` pins local and
  relay command execution to `1.94.0` with the `rustfmt` and `clippy`
  components. The installed `rustc`/Cargo were both `1.94.0`.
- **Lock refresh:** `cargo update` resolved 75 compatible package version
  updates under Rust 1.94 (Cargo reported 76 lock actions, including one new
  `rand_pcg` package; platform-specific removals account for the remainder).
- **Audit and suite:** `cargo audit` scanned 232 locked dependencies with no
  RustSec findings. `cargo fmt --check` and `cargo clippy -- -D warnings`
  passed. `cargo test` passed the 234-test baseline: 170 unit, 8 integration,
  14 mesh, 9 Pi-forward, 10 presence, 3 protocol-parity, and 20 rooms tests.
- **Follow-up (out of scope):** major migrations remain separate work:
  `axum` 0.7→0.8, `ed25519-dalek` 2→3, `rand` 0.8→0.10, and dev-only
  `reqwest` 0.12→0.13. Their direct constraints were not changed here.

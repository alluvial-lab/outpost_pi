---
id: story-refresh-relay-rust-toolchain-dependencies
kind: story
stage: implementing
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

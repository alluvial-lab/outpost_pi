---
id: story-migrate-outpost-pi-identity-built-in-kotlin
kind: story
stage: implementing
tags: [app, deps]
parent: feature-stack-currency-review
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Migrate outpost_pi_identity (owned) off legacy KGP to built-in Kotlin

Full built-in-Kotlin migration for our own plugin: KGP removal, compiler-options migration, SDK floor updates, example-app migration, dual-mode build tests. Research §3.1 for the treatment.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

---
id: story-migrate-app-agp9-built-in-kotlin
kind: story
stage: implementing
tags: [app, deps]
parent: feature-stack-currency-review
depends_on: [story-refresh-app-compatible-dependencies, story-migrate-outpost-pi-identity-built-in-kotlin, story-upgrade-app-settings-built-in-kotlin, story-upgrade-plus-plugins-built-in-kotlin, story-resolve-speech-to-text-built-in-kotlin]
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# App: AGP 9 + flip built-in Kotlin on (all plugins migrated)

App-side KGP/new-DSL migration; enable built-in Kotlin; APK build + smoke. Gated on all five KGP blockers.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

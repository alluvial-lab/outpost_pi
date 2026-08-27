---
id: story-resolve-speech-to-text-built-in-kotlin
kind: story
stage: implementing
tags: [app, deps, research]
parent: feature-stack-currency-review
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Resolve speech_to_text KGP blocker: upstream release vs minimal fork vs replacement

Decision story: check upstream for a built-in-Kotlin release; else evaluate minimal fork (KGP strip) vs replacement plugin. Decision + implementation recorded.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

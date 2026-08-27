---
id: story-upgrade-flutter-3-47-1-app
kind: story
stage: implementing
tags: [app, deps]
parent: feature-stack-currency-review
depends_on: [story-migrate-app-agp9-built-in-kotlin]
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Upgrade Flutter to 3.47.1 (APP-ONLY — cockpit dormant)

SCOPE REVISED (cockpit dormancy 2026-08-27): app + e2e-pairing + app-release pins to 3.47.1; NO macOS/appcast work (cockpit stays frozen 3.44.4). Pixel Fold UAT incl. stale-IME behavior check is the evidence gate.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

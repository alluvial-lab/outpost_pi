---
id: story-refresh-app-compatible-dependencies
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

# App: refresh compatible dependency set (17 locked updates incl. KGP-patched image_picker/url_launcher)

Apply the 17 compatible locked updates identified in feature-stack-currency-review §4 (incl. image_picker + url_launcher KGP-compatible patches). flutter pub upgrade within constraints; analyze + full suite green.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

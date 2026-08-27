---
id: story-upgrade-pi-sdk-and-node-floor
kind: story
stage: implementing
tags: [pi-extension, deps]
parent: feature-stack-currency-review
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-27
updated: 2026-08-27
---

# Pi SDK 0.80.6→0.84.3 adapter migration + Node engine floor correction

Fix declared Node floor (>=20 → >=22.19, required by SDK 0.80.6 TODAY) then the 0.84.3 adapter migration. Full extension suite + build green.

Findings, versions, and citations: feature-stack-currency-review.md (the
research item is the single source of truth for this migration program).
Note: story-unify-flutter-3-44-4-pins was completed at dormancy-setup time
(commit 80d9d8903: all four pins → 3.44.4) and is not spawned separately.

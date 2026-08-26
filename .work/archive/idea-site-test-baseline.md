---
id: idea-site-test-baseline
created: 2026-07-23
updated: 2026-08-26
tags: [site, testing]
status: folded
folded_into: feature-site-test-baseline (groom 2026-08-26)
---

# Site test baseline

`site/` is the only subproject with zero test files (advisor review
2026-07-23). Even a thin baseline — a smoke render test per route or a link/
metadata check wired into `pnpm lint`-adjacent CI — would give the marketing
surface a safety net. Also noted: `site/src/app/globals.css` is 2282 LOC and
may warrant a split when the next styling pass happens.

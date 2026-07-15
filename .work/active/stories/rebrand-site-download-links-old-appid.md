---
id: rebrand-site-download-links-old-appid
kind: story
stage: done
tags: [rebrand, site, release]
parent: feature-outpost-pi-distribution-ownership
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-12
updated: 2026-07-14
---

# Site download links point to old Play Store listing

## Context

Found by the deep review of the wire-stable migration feature. The site's download links still target the old Google Play listing (`work.jacobmoura.remotepi`), which cannot deliver the 0.1.0 app (`dev.kevoun.outpostpi`). Users following the link install an app whose old auth domain is rejected by the new relay.

Files affected:

- `site/src/app/download/page.tsx`;
- `site/src/app/tutorials/getting-started/page.tsx`;
- `site/src/components/landing/sections.tsx`.

The README's Play link is already marked “coming soon” (sideload-only).

## Required outcome

Disable or mark the site Play Store links as unavailable until the operator-owned listing exists. The published site must not direct users to the incompatible upstream application.

Run `pnpm lint` and `pnpm build` from `site/`.

## Implementation notes
- Files changed:
  - `site/src/components/landing/sections.tsx` — removed the Google Play store card and its now-unused `IconPlay` import.
  - `site/src/app/download/page.tsx` — replaced the old Play Store link with a "coming soon" note (0.1.0 sideload-only, new applicationId).
  - `site/src/app/tutorials/getting-started/page.tsx` — removed the Play Store link; directs to App Store + APK direct download, notes Google Play is coming soon.
- Verification: `corepack pnpm lint` clean; `corepack pnpm build` succeeded (18 static pages).
- `rg 'work.jacobmoura.remotepi' site/` returns no hits.
- Discrepancies from design: none.
- Adjacent issues parked: none (left `IconPlay` export in `icons.tsx` as harmless unused export; lint did not flag it).

## Review (2026-07-15)

**Verdict**: Approve - story verified by implement; fast-lane advance

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane: green build+test verification recorded by implement. Orchestrator re-verified the combined tree (extension 838 passed/3 skipped; relay all green; app analyze clean + 698 passed; protocol check + generate:rust:check clean; site lint+build clean).

---
id: rebrand-site-download-links-old-appid
kind: story
stage: implementing
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

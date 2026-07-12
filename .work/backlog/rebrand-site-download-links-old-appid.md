---
id: rebrand-site-download-links-old-appid
created: 2026-07-12
updated: 2026-07-12
tags: [rebrand, site, release]
---

# Site download links point to old Play Store listing (incompatible app)

## Context

Found by the deep review of the wire-stable migration feature. The site's
download links still target the old Google Play listing
(`work.jacobmoura.remotepi`), which cannot deliver the 0.1.0 app
(`dev.kevoun.outpostpi`). Users following the link install an app whose
old auth domain is rejected by the new relay.

Files affected:
- `site/src/app/download/page.tsx:354`
- `site/src/app/tutorials/getting-started/page.tsx:55`
- `site/src/components/landing/sections.tsx:140`

The README's Play link was already marked "coming soon" (sideload-only).

## What's needed

Disable or mark the site Play Store links as "coming soon" until the new
listing exists. Part of the external-surfaces follow-up epic, but should
be addressed before the site is published with 0.1.0 copy.

## Severity

Important (not blocking the code release, but blocking public site
publication). Defer to the external-surfaces follow-up epic.

## Found by

Deep review of `epic-rebrand-to-outpost-pi-wire-and-install-stable-migration`
(2026-07-12).

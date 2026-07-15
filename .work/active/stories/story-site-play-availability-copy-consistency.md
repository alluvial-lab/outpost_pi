---
id: story-site-play-availability-copy-consistency
kind: story
stage: implementing
tags: [site, bug, rebrand]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-14
---

# Make Google Play availability copy consistent across the site

## Review finding

**Severity:** Important

The old Play listing links are gone, and the download/tutorial pages say the new
listing is coming soon (`site/src/app/download/page.tsx:353-356` and
`site/src/app/tutorials/getting-started/page.tsx:57`). The landing surface still
claims users can "Get it on ... Google Play" at
`site/src/components/landing/sections.tsx:160-162`, even though its Play card was
removed. The download page also hard-codes the transitional `0.1.0` at line 353
while displaying release metadata dynamically elsewhere.

## Required outcome

Use one current availability statement across landing, download, and getting
started: Google Play is unavailable/coming soon until an owned listing exists,
with direct APK as the Android path. Avoid a hard-coded release number for this
ongoing distribution state. Run site lint/build and grep for both old listing
links and affirmative Play-availability claims.

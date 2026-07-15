---
id: story-site-play-availability-copy-consistency
kind: story
stage: done
tags: [site, bug, rebrand]
parent: epic-rebrand-external-surfaces
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-15
updated: 2026-07-15
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

## Implementation notes
- Files changed:
  - `site/src/components/landing/sections.tsx` — the `GetApp` intro paragraph no longer says "Get it on the App Store or Google Play"; it now reads App Store + APK direct, with "Google Play for the new listing is coming soon."
  - `site/src/app/download/page.tsx` — removed the hard-coded `0.1.0`; the sideload/coming-soon note now says "the current release" instead of a pinned version.
- `site/src/app/tutorials/getting-started/page.tsx` already said coming soon (prior story); no change needed.
- All three surfaces (landing, download, getting-started) now consistently state Google Play is coming soon.
- Verification: `corepack pnpm lint` + `corepack pnpm build` green (18 static pages).
- `rg 'Google Play|coming soon|work.jacobmoura.remotepi' site/src/` confirms consistency; no old listing links remain.
- Discrepancies from design: none.
- Adjacent issues parked: none.

## Review (2026-07-15, second pass)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Deep-feature second-pass verification confirmed landing, download, and getting-started all describe Google Play as coming soon, retain direct APK as the Android path, contain no old Play URL/application ID, and no longer hard-code `0.1.0`. Site lint/build passed. Story advanced `review -> done`.

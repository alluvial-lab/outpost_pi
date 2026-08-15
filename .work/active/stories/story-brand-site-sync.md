---
id: story-brand-site-sync
kind: story
stage: implementing
tags: [branding, site]
parent: feature-public-flip-branding-and-exposure
depends_on: [story-brand-icon-regen-sweep]
release_binding: null
gate_origin: null
created: 2026-08-14
updated: 2026-08-15
---

# Site sync — Phosphor Beacon + v2 mark

1. Tokens port: map `.mockups/design-system/tokens.css` into the site's
   Tailwind 4/PostCSS variables (bg/elevated/border/text/muted/accent/status,
   both modes; the site is currently neutral-only — adopt dark-native +
   light dual-mode).
2. Logo/favicon: use the v2 SVGs from the icon story; retire all stale
   variants (audit item 4).
3. Typography: Space Mono via next/font (Google) — headings, body, code,
   wordmark in hero/hero-adjacent copy.
4. README hero: banner.png from the icon story; confirm `branding/logo-full.svg`
   refs in README point at `logo-full-dark.svg` (old name deleted).
5. Screenshot retake (audit item 5): after the app theme story ships, retake
   `screenshot-app.png` on a phone build, restore `branding/screenshot-app.png`
   + site cockpit page usage.

Verify: `pnpm lint` + `pnpm build` green; dark/light toggle (if present)
renders both modes AA.

## Implementation run

- Dependency `story-brand-icon-regen-sweep` is `done` with green asset/hash
  evidence (`56bcbcd`).
- Ownership: direct host implementation under `site/` plus the scoped root
  README reference; the icon story already supplied canonical SVG/favicon
  assets.
- Capability: `openai-codex/gpt-5.6-sol`, high (caller-selected).
- Screenshot retake is explicitly deferred: this VM has no attached phone, so
  the deleted pre-theme screenshot will not be restored from stale imagery.

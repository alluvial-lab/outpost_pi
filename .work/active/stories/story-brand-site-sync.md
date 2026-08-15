---
id: story-brand-site-sync
kind: story
stage: done
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

## Implementation notes

- Ported the locked Phosphor Beacon dark/light neutral, accent, status,
  typography, spacing, and radius values into Tailwind 4/theme CSS variables.
  Existing site aliases now derive from those roles instead of duplicating the
  old black/white/sky-blue palette.
- Added system light-mode following plus explicit `data-theme="dark|light"`
  support. The site has no toggle control today, so the existing journey remains
  system-driven while a future control can use the already-supported contract.
- Replaced hardcoded dark-only component fills/glows with mode-aware variables,
  including the animated mesh, phone mock, terminal, docs code pills/tables,
  warning callouts, and screenshot shadows.
- Replaced the three-font stack with Space Mono 400/700 (+ italic) through
  `next/font/google`; display, body, code, and wordmark roles share it.
- Replaced the stale inline header and Open Graph π marks with canonical
  Constellation III geometry, retained the canonical `public/logo.svg` and App
  Router icon from the icon story, and deleted the unused divergent
  `public/logo-foreground.svg` variant.
- Updated the root README hero reference to `branding/logo-full-dark.svg`.
- Screenshot deviation: no phone is attached to this VM, so the deleted
  pre-theme `branding/screenshot-app.png` was not retaken or restored. This is
  deferred to device UAT and does not block the site build.
- Completion review fix pass: cockpit hero removed as upstream-identical; retake with rebranded build pending phone.

## Verification evidence

- Completion review fix pass — refreshed README logo references and brand-styled wordmarks, removed the upstream-identical Cockpit hero asset, and retired its generator copy.
- `cd site && COREPACK_HOME=/tmp/corepack-home corepack pnpm
  --config.store-dir=/tmp/pnpm-store lint` — PASS.
- Same environment with `pnpm build` — PASS: Next 16 production compile,
  TypeScript, and all 18 static routes (including `/icon.svg` and
  `/opengraph-image`). `--config.store-dir` was used because this pnpm version
  rejects the caller's equivalent `--store-dir` spelling at the run boundary.
- Canonical asset byte checks — PASS: `site/public/logo.svg` and
  `site/src/app/icon.svg` both match `branding/logo-full-dark.svg`.
- Contrast script — PASS: primary, muted, accent-on-background, and on-accent
  pairs are all ≥4.5:1 in both modes (minimum 5.67:1).
- Custom-property dependency scan — PASS: 78 variables, no alias cycles.
- Grep for old blue/font/logo references — zero matches under site source;
  root README references only `branding/logo-full-dark.svg`.
- `git diff --check` — PASS.

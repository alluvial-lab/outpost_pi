---
id: story-brand-icon-regen-sweep
kind: story
stage: implementing
tags: [branding, icons]
parent: feature-public-flip-branding-and-exposure
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-14
updated: 2026-08-15
---

# Icon regeneration sweep — Constellation III across every surface

Generate all launcher/favicon PNGs from `branding/` v2.0 SVGs using the
on-VM Pillow rasterizer (mark is rects/circles/lines; 4× supersample +
LANCZOS; no external SVG converter needed — Pillow 11.1 present).

Surfaces (each currently byte-identical to upstream art — the audit's item 1):

1. **app Android adaptive**: `ic_launcher_foreground.png` + `ic_launcher_monochrome.png`
   (432px, all densities) from logo-foreground/monochrome; background = solid
   #0D1210 layer (adaptive bg resource).
2. **app iOS**: full AppIcon.appiconset (20–1024) from logo-full-dark, no alpha.
3. **cockpit macOS**: app_icon_16…1024 from logo-full-dark.
4. **cockpit Windows**: `app_icon.ico` (multi-size) from logo-full-dark.
5. **site**: favicon (32/16) + `site/public/logo.svg` + `site/app/icon.svg`
   replaced with the v2 mark (SVG copies; kills the stale divergent variants —
   audit item 4).
6. **README hero**: banner.png regenerated from banner.svg at 1280×640
   (needs Space Mono present for the wordmark, or convert text to paths first).

Verify: `git hash-object` every regenerated PNG ≠ upstream raw counterpart;
`flutter analyze` untouched (asset-only change). Also delete
`branding/screenshot-app.png` here or in the screenshot story (stale upstream
screenshot — audit item 5); recommend deleting here, retake in story-brand-site-sync.

## Implementation run

- Ownership: cohesive host implementation because no worker-subagent adapter is
  available in this harness; the asset sweep is the shared dependency for both
  downstream stories.
- Capability: `openai-codex/gpt-5.6-sol`, high (caller-selected).
- Plan: render canonical geometry at 4× with Pillow/LANCZOS, preserve every
  platform export matrix, hash-compare tracked app/cockpit assets against
  upstream, then advance this child story directly to `done` on green evidence.

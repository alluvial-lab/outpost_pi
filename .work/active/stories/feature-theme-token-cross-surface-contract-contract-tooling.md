---
id: feature-theme-token-cross-surface-contract-contract-tooling
kind: story
stage: done
tags: [branding, site, testing]
parent: feature-theme-token-cross-surface-contract
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Establish the shared brand-contract fixture and canonical mark projection

## Checkpoint

Create the root/site-tooling anchor for the cross-surface contract. A standard-library Python synchronizer reads `.mockups/design-system/tokens.css` into one checked-in `branding/theme-contract.json` golden fixture and reads `branding/logo-foreground.svg` into one typed geometry model. The same geometry model drives Pillow rasterization and a checked-in generated TypeScript projection consumed by the Open Graph image. CI checks generated projections for drift and routes contract changes into the app, cockpit, and site lanes.

This is intentionally golden-based rather than Dart code generation: mobile and desktop retain their native semantic palettes, while the fixture makes their shared contract roles comparable without adding generated production Dart or a CSS parser to either Flutter build.

## Acceptance evidence

- `python3 scripts/sync-brand-contracts.py --check` exits zero only when `branding/theme-contract.json` and `site/src/generated/constellation_mark.generated.ts` match their canonical CSS/SVG inputs.
- `scripts/generate-brand-assets.py` obtains Constellation III geometry from `branding/logo-foreground.svg`; no coordinate/radius/stroke literals remain in the rasterizer.
- `site/src/app/opengraph-image.tsx` consumes the generated mark projection; no independent mark geometry remains in the component.
- CI runs the synchronizer for changes to tokens, canonical branding SVGs, brand scripts, or generated projections, and contract changes trigger the app, cockpit, and site verification lanes.
- `pnpm lint && pnpm build` passes from `site/`; the brand synchronizer check passes from the repository root.

## Ordering constraint

This checkpoint is the anchor for both Flutter port checks. Complete it before either surface adopts the fixture.

## Implementation

- Added the restricted standard-library parser/projection module in
  `scripts/brand_contract.py` and the deterministic synchronizer at
  `scripts/sync-brand-contracts.py`.
- `branding/theme-contract.json` is the checked-in dark/light role fixture with
  the WCAG AA normal-text threshold. The parser validates supported selectors,
  color values, duplicate/missing roles, and the duplicated dark media block.
- `branding/logo-foreground.svg` now drives Pillow rasterization through the
  validated `MarkGeometry` model and the generated
  `site/src/generated/constellation_mark.generated.ts` projection. The OG
  component consumes that projection instead of carrying mark coordinates.
- Added the `brand-contract` CI freshness job and routed canonical contract
  paths to the app, cockpit, and site jobs.

## Verification

- `python3 scripts/sync-brand-contracts.py --check` — PASS.
- `python3 -m py_compile scripts/brand_contract.py scripts/sync-brand-contracts.py scripts/generate-brand-assets.py` — PASS.
- `python3 scripts/generate-brand-assets.py` — PASS; generated assets were
  unchanged because the parsed SVG geometry matches the prior renderer.
- Parser boundary checks for invalid CSS and canonical SVG geometry — PASS.
- `cd site && corepack pnpm lint` — PASS.
- `cd site && corepack pnpm build` — PASS.

The requested direct-read design was sufficient; no implementation deviation
was required.

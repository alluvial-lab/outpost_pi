---
id: feature-public-flip-branding-and-exposure-brand-evidence-closure
kind: story
stage: implementing
tags: [branding, site]
parent: feature-public-flip-branding-and-exposure
depends_on: [story-brand-site-sync]
release_binding: null
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Close the residual brand-evidence gap without restoring stale imagery

The v0.5.0 brand cascade removed the upstream-derived screenshot rather than
publishing an unverified replacement. The current Cockpit marketing page has no
screenshot, but one sentence still claims that a screenshot appears above it.
This checkpoint makes the no-screenshot state internally honest and records the
current brand evidence; it does not regenerate completed assets or invent a
mock capture.

## Design element

- Remove the stale “screenshot up top” claim from
  `site/src/app/cockpit/page.tsx` while preserving the surrounding mesh copy.
- Keep `branding/screenshot-app.png` absent and do not add a screenshot until a
  real, current Outpost-Pi app or Cockpit capture exists. A future marketing
  capture is additive work, not a blocker for removing upstream holdovers.
- Re-run the existing brand anchors rather than touching completed app/Cockpit
  theme or icon files: generated platform icons differ from upstream, runtime
  colors use Phosphor Beacon, site SVGs match the canonical dark mark, and the
  vestigial font names remain absent.

## Acceptance evidence

- [ ] `site/src/app/cockpit/page.tsx` contains no claim about a missing
  screenshot and introduces no replacement image.
- [ ] `git ls-files branding/screenshot-app.png` and tracked site screenshot
  searches return no stale artifact.
- [ ] Canonical site SVG comparisons pass and the app/Cockpit upstream hash
  comparisons retain zero identical icon/theme holdovers.
- [ ] Schyler/Trajan searches remain empty and Space Mono remains wired across
  app, Cockpit, and site.
- [ ] `cd site && pnpm lint && pnpm build` passes.

## Ordering constraint

`story-brand-site-sync` is already done and supplies the canonical site assets.
This checkpoint may proceed in parallel with the public-tree exposure guard; the
history rescrub waits for both so it rewrites the final feature tree.

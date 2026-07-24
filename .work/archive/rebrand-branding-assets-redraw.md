---
id: rebrand-branding-assets-redraw
status: superseded
superseded_by: story-epic-rebrand-external-surfaces-hostname-migration-branding-svg-redraw
created: 2026-07-12
updated: 2026-07-24
stage: done
release_binding: v0.3.0
tags: [rebrand, branding, design]
---

# Branding assets (banner.svg, logo) still say "Remote Pi"

## Context

The mechanical rename covered code/docs but the branding SVG assets still
contain "Remote Pi" text and the old `remote-pi.jacobmoura.work` URL:
- `branding/banner.svg` — "Remote Pi" wordmark + `pi install npm:remote-pi` +
  `remote-pi.jacobmoura.work` URL

These are image assets with layout/typography considerations — a sed replace
risks breaking the SVG layout. They need a proper redraw or manual edit.

## What's needed

- Update `branding/banner.svg` (and any other branding SVGs) to the
  `Outpost-Pi` wordmark + `outpost-pi` npm install + the new URL (TBD —
  external surfaces are deferred to the follow-up epic).
- Review `branding/logo-full.svg` and other logo assets for "Remote Pi" text.

## Severity

Important (not blocking the 0.1.0 code release, but the branding assets
ship in the README and site). Defer to the external-surfaces follow-up epic
or handle as a small design task.

## Found by

Review of `epic-rebrand-to-outpost-pi-mechanical-rename` (2026-07-12).

---
id: story-epic-rebrand-external-surfaces-hostname-migration-branding-svg-redraw
kind: story
stage: implementing
tags: [rebrand, branding, design]
parent: epic-rebrand-external-surfaces-hostname-migration
depends_on: [story-epic-rebrand-external-surfaces-hostname-migration-mechanical-replacement]
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Manually redraw the banner branding text

## Scope

Absorbs backlog item `rebrand-branding-assets-redraw`. Manually update only
`branding/banner.svg`; do not run a repository-wide replacement or line-based
`sed` against SVG assets. The file's text positioning, available right-panel
width, and typography are part of the asset layout.

## Required banner content

Update the three text nodes in `branding/banner.svg` to:

- wordmark: `Outpost-Pi`
- install command: `pi install npm:outpost-pi`
- public URL: `outpost-pi.kevoun.com`

Keep the 1280×640 canvas, left-side Pi mark, dark palette, and existing visual
hierarchy. Adjust only the affected text attributes (font size, letter spacing,
or coordinates) when necessary to keep the longer wordmark and URL wholly
inside the right panel; do not alter unrelated SVG geometry.

`branding/logo-{full,background,foreground,monochrome}.svg` were inspected:
they contain no legacy wordmark, command, or hostname, so no edit is required.

## Acceptance criteria

- [ ] `banner.svg` is well-formed SVG and preserves its 1280×640 viewBox/canvas.
- [ ] The rendered banner visibly has the Outpost-Pi wordmark, the
  `outpost-pi` npm command, and `outpost-pi.kevoun.com`; none is clipped,
  overlapped, or pushed outside the right panel.
- [ ] No `Remote Pi`, `npm:remote-pi`, or `remote-pi.jacobmoura.work` remains
  in the banner.
- [ ] The other branding SVGs remain byte-for-byte unchanged unless a manual
  review discovers a previously missed legacy text element.
- [ ] No raster export or generated asset is committed.

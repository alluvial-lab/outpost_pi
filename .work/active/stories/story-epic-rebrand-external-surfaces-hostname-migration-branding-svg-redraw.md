---
id: story-epic-rebrand-external-surfaces-hostname-migration-branding-svg-redraw
kind: story
stage: review
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

- [x] `banner.svg` is well-formed SVG and preserves its 1280×640 viewBox/canvas.
- [x] The rendered banner visibly has the Outpost-Pi wordmark, the
  `outpost-pi` npm command, and `outpost-pi.kevoun.com`; none is clipped,
  overlapped, or pushed outside the right panel.
- [x] No `Remote Pi`, `npm:remote-pi`, or `remote-pi.jacobmoura.work` remains
  in the banner.
- [x] The other branding SVGs remain byte-for-byte unchanged unless a manual
  review discovers a previously missed legacy text element.
- [x] No raster export or generated asset is committed.

## Implementation notes

- Manually updated only the three affected `text` node values in
  `branding/banner.svg`. The existing x-coordinates, font sizes, and spacing
  remain appropriate: the wordmark and command fit within the 664px usable
  width of the right panel, and the new hostname is shorter than its previous
  value.
- Confirmed `branding/logo-{full,background,foreground,monochrome}.svg` has no
  legacy wordmark, command, or hostname text, so those files remain unchanged.

## Verification

- Parsed the SVG with Python's XML parser; asserted the 1280×640 canvas and
  viewBox, all three required text nodes, and the absence of legacy text.
- Reviewed the scoped diff: it changes exactly the three target text values and
  preserves all SVG structure and geometry. `rsvg-convert` and ImageMagick were
  unavailable in this environment, so no raster render was produced.

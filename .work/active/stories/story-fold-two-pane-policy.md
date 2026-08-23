---
id: story-fold-two-pane-policy
kind: story
stage: implementing
tags: [app, ux]
parent: feature-fold-usability-pass
depends_on: ['story-fold-golden-harness-fidelity']
release_binding: null
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# Two-pane eligibility needs master+min-detail; divider contrast; keyboard isolation

Review findings 8, 9, 17. Files: `lib/routing/adaptive.dart`,
`lib/routing/app_router.dart`, `lib/ui/core/themes/`.

- Split policy: today shortestSide >= 600 splits, but master is FIXED 360
  (`app_router.dart:465`) → a 600dp window yields a 240dp detail pane
  (unusable). New rule: split only when width - 360 >= 320 (i.e. width >=
  680 in the splitting orientation) — express as `kMinDetailWidth = 320`
  beside `kTabletBreakpoint`; keep shortestSide classification for phone
  vs tablet semantics, add the pane-budget test for the split decision.
  Pixel Fold unfolded (701/842) still splits; 600-679dp windows (small
  tablets, 1:1 splits on ~600dp unfoldeds) stay single-pane.
- Divider: 1px #1E2620 on #0D1210 is ~1.2:1 contrast — invisible. Use a
  stronger border/divider token (or tonal pane difference); keep 1dp
  geometry; verify against the Phosphor Beacon tokens
  (`.mockups/design-system/tokens.css` is the contract — pick the nearest
  existing stronger token; do not invent an off-system color).
- Keyboard: both panes inherit full-window viewInsets today. Strip
  viewInsets (and the bottom inset it drives) from the MASTER pane's
  MediaQuery so the session list does not resize while the detail's
  keyboard is open; add the two-pane keyboard capture from story 1 as the
  regression proof.

## Verification
Widget tests: split decision at 599/600/679/680/701/842dp widths; divider
token contrast >= existing border usage; master pane height unchanged when
detail viewInsets=280. Goldens regreen.

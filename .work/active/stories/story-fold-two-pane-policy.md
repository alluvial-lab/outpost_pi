---
id: story-fold-two-pane-policy
kind: story
stage: done
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

## Implementation

- Kept `isWideLayout` as the shortest-side tablet classifier and added the
  orientation-specific `canUseTwoPaneLayout` pane budget: fixed 360dp master +
  new 320dp minimum detail. The shell now splits at 680dp, preserving Fold
  701/842 layouts while collapsing 600–679dp windows.
- Added the contract-backed `borderStrong` semantic token (`#2A342C` dark,
  `#C2CEC3` light) and used it for the 1dp pane divider; tests prove it improves
  contrast over the ordinary hairline token in both themes.
- Centralized master-pane MediaQuery derivation so detail keyboard viewInsets
  are removed, stable bottom safe padding is restored, and divider-facing
  padding alone is stripped. A 280dp detail keyboard no longer changes master
  body height.
- Updated the production-mirror golden shell and regenerated all 144 captures.

Verification: adaptive/theme widget tests, full golden matrix, `flutter analyze`,
and `flutter test --exclude-tags e2e --concurrency=2`.

## Review closure (2026-08-23)

- Moved keyboard isolation below the master branch Navigator so only the persistent Home surface receives stripped insets; master-owned modal routes retain the real keyboard inset. The 842×701 settings-modal test uses a 280dp inset and proves Home height stays stable while modal content receives 280dp bottom padding.
- Added the 1dp divider to the pane budget. Width 680 now remains single-pane and 681 is the first split width, preserving the complete 320dp detail minimum.

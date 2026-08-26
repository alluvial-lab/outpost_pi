---
id: backlog-app-fold-not-using-full-vertical-screen
created: 2026-08-25
updated: 2026-08-26
tags: [app, bug, ux]
status: superseded
superseded_by: story-fix-app-fold-vertical-screen (done, v0.8.1) — code-verified groom 2026-08-26
---

Promoted to `story-fix-app-fold-vertical-screen`.

# Pixel Fold: app doesn't use full vertical screen at regular phone width

Operator report (2026-08-25, Pixel Fold, 0.7.x-0.8.x builds): in regular
phone width (folded/narrow), the app does not use the full vertical screen
— something leaves unused vertical space, as if the window never grew back
after a keyboard cycle. Operator hypothesis: incorrect conversion back
from keyboard mode.

## Suspects (from this session's history — check first)

1. **Compact-composer thresholds** (0.6.1+ hysteresis fix): `height -
   viewInsets.bottom < 280` enters compact; exits only above 360dp. On the
   Fold's folded height (~797dp) minus a keyboard (~280dp) ≈ 517dp — that
   should exit cleanly… but if `viewInsets.bottom` doesn't return to 0
   (Android inset leakage after IME close, or our master-pane
   `removePadding`/inset isolation from the fold pass interfering), the
   app stays in a shrunken layout while no keyboard is visible.
2. **Master-pane viewInsets isolation** (acbcd958 + gate-fix a9b15458):
   the fold pass strips keyboard insets from the master pane and re-supplies
   them to master-owned modals — a bug there could pin a stale inset.
3. **The grid/mesh battery's windowed emulator** rendered 1080x2400 folded
   geometry fine in goldens — real-device WindowManager behavior (Fold
   posture transitions) is NOT covered by any golden; this may be
   device-only inset behavior.

## Work

Reproduce on the Fold emulator with posture transitions + keyboard
open/close cycles (folded): inspect `MediaQuery.viewInsets.bottom` and
`size` after keyboard closes — does an inset stay pinned? Assert full-
height usage in a widget test simulating the inset ramp down to zero. Fix
at whichever layer holds the stale value; add the posture/keyboard-cycle
case to the fold golden matrix if it can be rendered headlessly.

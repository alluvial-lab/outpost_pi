---
id: story-fold-home-sheets-adaptivity
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

# Home + sheets adaptivity: compact narrow header, wide list cap, height-adaptive sheets

Review findings 7 (home), 11, 12, 13. Files: `lib/ui/home/**`,
`lib/ui/chat/quick_actions/widgets/**`, `lib/ui/chat/widgets/attach_sheet.dart`,
`lib/ui/pairing/widgets/paste_qr_sheet.dart`.

- Narrow (234dp): home header overflow — wordmark + relay subtitle +
  settings + three filter segments. Below ~280dp: compact title treatment
  (smaller wordmark or stacked), filters collapse to icons or wrap.
- Wide single-pane (797×411 landscape phone): session rows stretch ~800dp,
  status dots far from titles. Cap + center the list content (~560dp) in
  wide single-pane; app header stays full-width.
- Sheets: Quick Actions is a non-scrollable min-size Column overflowing in
  landscape (quick_actions_sheet.dart:135-184); Paste QR likewise + puts
  the keyboard inset OUTSIDE its column (paste_qr_sheet.dart:24-28), CTA
  clipped in landscape. Make sheet content scrollable + height-constrained
  (maxHeight fraction with min), keep keyboard inset INSIDE the sheet's
  padded area; explicit width caps (~460 attach, ~560-640 richer sheets)
  instead of relying on Material's implicit 640 bottom-sheet cap; deliberate
  landscape treatment (centered dialog-style on low height).

## Verification
Widget tests: no overflow for any sheet at 797×411 (+keyboard), 234×842;
list content width capped in wide single-pane; filter/header compact mode
asserted below 280dp. Goldens.

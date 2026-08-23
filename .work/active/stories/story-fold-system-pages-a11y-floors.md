---
id: story-fold-system-pages-a11y-floors
kind: story
stage: done
tags: [app, ux, a11y]
parent: feature-fold-usability-pass
depends_on: ['story-fold-golden-harness-fidelity']
release_binding: null
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# System pages responsive-center + touch-target and type floors

Review findings 14, 15, 16. Files: `lib/ui/sync_required/**`,
`lib/ui/storage_recovery/**`, `lib/ui/chat/widgets/input_bar.dart`,
`lib/ui/home/**`, quick-actions/model-picker sheets.

- ResponsiveCenter: sync-required uses full-width 24dp padding
  (sync_required_page.dart:62-67), storage-recovery full-width 32dp
  (transcript_storage_recovery_page.dart:101-108) — both stretch on
  842dp. Wrap in the existing ResponsiveCenter (460dp) like onboarding;
  recovery column becomes scrollable, preserving centered placement when
  it fits.
- Hit floors: quick-actions/attach buttons 32×32 (input_bar.dart:813,635),
  send/stop 38×38 (:927,:610), home filter segments 8dp vertical padding,
  thinking/model chips compact. Keep compact VISUALS but guarantee 48×48
  effective hit regions (padding-based expansion or IconButton minimums),
  semantics labels on gesture-only controls.
- Type floors: operational metadata at 10-11sp (chat status
  chat_page.dart:196,557; sync instructions 10.5; model badges 9sp) —
  raise operational text to >=12sp; badges below 12sp only with accessible
  alternatives (tooltip/semantics).

## Verification
Widget tests: tap-target sizes >=48 for the listed controls (probe via
hitTestable bounds at gesture position); no text style <12sp in the listed
operational paths (lint-style test walking the trees); both system pages
centered+capped at 842dp and scrollable at 797×411. Goldens.

## Implementation notes
- Execution capability: sol/high, selected by the caller for a cross-widget accessibility and responsive-layout slice.
- Review weight: standard (project default); this child checkpoint has no independent review, and the caller deferred feature review to the orchestrator.
- Files changed: sync-required and transcript-storage-recovery pages; chat composer/status, Home filters, quick-actions thinking segments, model-provider chips/badges; focused widget tests; fold golden overflow policy.
- Tests added/updated: responsive-center, recovery scrolling, explicit 12sp floors, 48dp target geometry, gesture semantics, compact-badge accessible alternatives, and the full 144-image fold matrix with overflow failures.
- Simplification: removed the final geometry overflow allowlist and its conditional handling; every matrix overflow now fails directly.
- Discrepancies from design: none.
- Adjacent issues parked: none.

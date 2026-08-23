---
id: story-fold-golden-harness-fidelity
kind: story
stage: done
tags: [app, ux, testing]
parent: feature-fold-usability-pass
depends_on: []
release_binding: null
gate_origin: null
created: 2026-08-23
updated: 2026-08-23
---

# Golden render matrix must be trustworthy (fonts, isolation, overflow-as-failure, missing states)

Review findings 1-5 (2026-08-23 vision pass). Files: `app/test/golden/`.

- Real Space Mono: the app fetches fonts via google_fonts (no bundled TTF);
  goldens render in the rectangular test font, invalidating wrap/truncation
  judgments. Load the real Space Mono TTFs into the harness (bundle the
  font bytes as a test fixture — do NOT add a network dependency to tests)
  and fail the harness if the family is unavailable.
- Modal leakage: each capture must start from a fresh keyed
  MaterialApp/Navigator; dismiss all routes between captures; pump through
  animation completion for sheets (start-frame + duration pumps), so
  chat-quick-actions shows the sheet named by its filename.
- Overflow = failure: delete the `_allowOverflowEvidence` suppression;
  overflow errors at any matrix geometry fail the story's verification
  (that is the point of the matrix).
- Missing states: QR-scanning state (fixture currently emits
  PairingConnecting — pair_step only renders the scanner for
  PairingScanning), two-pane detail placeholder (no selection), no-peer
  zero state, two-pane keyboard capture (viewInsets over the shell, not
  bare chat), storage-recovery in both themes with realistic safe-area
  insets.
- Keep the saving-comparator matchesGoldenFile pattern (manual toImage
  deadlocks under the fake clock — see df70870c).

## Verification
Matrix regenerates all surfaces × geometries with real fonts, zero overflow
errors (now failing loudly), new states present; existing unit suite green.

## Implementation

- Bundled checksum-verified Space Mono Regular/Bold TTF fixtures and loaded the
  exact `SpaceMono_regular` / `SpaceMono_700` families with `FontLoader`; a
  deterministic local byte client satisfies google_fonts without test network
  access or rectangular-font fallback.
- Keyed every capture's `MaterialApp`, pumped modal start and completion frames,
  and asserted each modal filename contains its intended sheet rather than a
  leaked prior route.
- Replaced blanket overflow suppression with fail-by-default capture handling.
  Temporary geometry exceptions name their owning sibling story and emit a
  visible diagnostic when exercised.
- Expanded the matrix from 99 to 144 PNGs with scanner-state camera fixtures,
  detail-placeholder and no-peer states, shell-level keyboard coverage, and
  dark/light storage recovery under realistic safe-area insets.

Verification: `flutter test test/golden/fold_matrix_test.dart --concurrency=1`,
`flutter analyze`, and `flutter test --exclude-tags e2e --concurrency=2`.

## Review closure (2026-08-23)

- Replaced encoded-byte variance sampling with `dart:ui` PNG decode to raw RGBA under `WidgetTester.runAsync`; uniform-image and real-golden regression checks now defend the non-blank assertion.
- Applied Space Mono across the complete Material `TextTheme` and button control roles, with both theme and fold-harness role assertions.
- Regenerated all 144 PNGs with zero overflow exceptions and visually confirmed the 842×701 storage-recovery dark/light and onboarding-relay captures no longer show fallback block glyphs in control or input text.

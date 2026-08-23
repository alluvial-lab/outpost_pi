---
id: story-fold-golden-harness-fidelity
kind: story
stage: implementing
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

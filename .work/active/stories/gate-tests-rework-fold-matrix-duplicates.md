---
id: gate-tests-rework-fold-matrix-duplicates
kind: story
stage: done
tags: [testing, refactor, app]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: tests
created: 2026-08-24
updated: 2026-08-24
---

# Remove byte-identical fold-matrix captures and vacuous file assertions

## Priority
Low

## Value evidence
Item: `story-fold-golden-harness-fidelity`. SHA-256 grouping of the generated
144-PNG matrix proves 15 redundant non-split captures: at 234, 350, 350@1.3,
411, 467, and 797dp widths, `two-pane-shell` and
`two-pane-detail-placeholder` are byte-identical to `home`; the
`two-pane-keyboard` capture is also identical at 234, 350, and 467dp. Those
surfaces collapse to Home by contract, yet the matrix renders all three for
every geometry (`app/test/golden/fold_matrix_test.dart:150-176`). Separately,
`writeFoldPng` already throws if the file is missing/empty
(`app/test/golden/fold_matrix_capture.dart:143-149`), making four downstream
file-existence expectations at `fold_matrix_test.dart:366`, `:425`, `:460`, and
`:499` postcondition re-assertions that cannot add confidence.

## Gap type
low-value-test-removal

## Suggested test
```dart
// Build the matrix from applicability predicates: emit two-pane variants only
// where canUseTwoPaneLayout is true; retain one breakpoint decision test for
// collapsed Home behavior. Remove file-existence assertions already enforced
// by writeFoldPng, while retaining overflow, decoded-variance, font, modal
// isolation, and true split/keyboard evidence. Assert expected surface keys so
// pruning cannot silently drop a unique contract.
```

## Test location (suggested)
`app/test/golden/fold_matrix_test.dart`

## Implementation

- Before deleting captures, verified the gate evidence from the 144-PNG run:
  SHA-256 grouping showed 15 redundant non-split captures — shell and detail
  placeholder at `234`, `350`, `350@1.3`, `411`, `467`, and `797` widths, plus
  keyboard at `234`, `350`, and `467`. These geometries fail the production
  `canUseTwoPaneLayout` pane-budget predicate and collapse to Home.
- The matrix now applies that production predicate, retains the three two-pane
  surfaces only for `701x842`, `842x701`, and `701x842-fs1.3`, and asserts the
  complete expected capture-key set (126 unique PNGs instead of 144).
- Removed four file-existence assertions because `writeFoldPng` already fails
  on missing or empty output; variance and surface-specific assertions remain.

## Verification

- `cd app && PATH=$PWD/../.tools/flutter/bin:$PATH flutter test test/golden/` — 2 tests passed.

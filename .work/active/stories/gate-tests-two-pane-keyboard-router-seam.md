---
id: gate-tests-two-pane-keyboard-router-seam
kind: story
stage: implementing
tags: [testing, app]
parent: null
depends_on: []
release_binding: v0.7.0
gate_origin: tests
created: 2026-08-24
updated: 2026-08-24
---

# Drive keyboard ownership through the production two-pane router

## Priority
High

## Value evidence
Item: `story-fold-two-pane-policy`. The user-visible contract is that a detail
composer keyboard does not resize Home, while a master-owned modal still sees
and pads for the real inset. Current focused tests build synthetic Rows and
Navigators around `masterPaneMediaQueryData`
(`app/test/routing/adaptive_test.dart:464-610`). The render matrix explicitly
uses `FoldProductionShellMirror` "without booting GoRouter"
(`app/test/golden/fold_matrix_fixtures.dart:615-652`). Neither test executes the
actual split decision and separate Home-route wrapper in
`app/lib/routing/app_router.dart:446-499`, so route/navigator wiring can regress
while both mirrors remain green.

## Gap type
e2e-seam / public UI interaction

## Suggested test
```dart
// Pump the production router at 842x701 with a selected detail session.
// Focus/type in the detail composer and apply a 280dp view inset: assert Home's
// bounds and selection stay stable while detail receives the inset.
// Then open a master-owned rename/settings modal, focus its field, and assert
// the modal receives 280dp padding and remains hit-testable while Home stays
// isolated. Exercise navigation/pop so nested/root Navigator ownership is real.
```

## Test location (suggested)
`app/test/routing/app_router_test.dart`

---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui-workspace-navigation-review
kind: story
stage: review
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-ui
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Translate workspace/navigation/dialog widgets and review UI literal

## Scope

Own exactly these files:

- `cockpit/lib/app/cockpit/ui/widgets/agent_edit_dialog.dart`
- `cockpit/lib/app/cockpit/ui/widgets/cockpit_topbar.dart`
- `cockpit/lib/app/cockpit/ui/widgets/confirm_dialog.dart`
- `cockpit/lib/app/cockpit/ui/widgets/empty_pane.dart`
- `cockpit/lib/app/cockpit/ui/widgets/file_tree_panel.dart`
- `cockpit/lib/app/cockpit/ui/widgets/history_dialog.dart`
- `cockpit/lib/app/cockpit/ui/widgets/model_picker.dart`
- `cockpit/lib/app/cockpit/ui/widgets/pane_divider.dart`
- `cockpit/lib/app/cockpit/ui/widgets/pane_view.dart`
- `cockpit/lib/app/cockpit/ui/widgets/projects_rail.dart`
- `cockpit/lib/app/cockpit/ui/widgets/subfolder_dialog.dart`
- `cockpit/lib/app/cockpit/ui/widgets/update_card.dart`
- `cockpit/lib/app/cockpit/ui/widgets/welcome_view.dart`
- `cockpit/lib/app/cockpit/ui/widgets/widgets.dart`
- `cockpit/lib/app/cockpit/ui/widgets/workspace_avatar.dart`
- `cockpit/lib/app/cockpit/ui/widgets/workspace_settings_dialog.dart`
- `cockpit/lib/app/cockpit/ui/widgets/worktree_create_dialog.dart`

Fifteen files carry PT comments/docs. `update_card.dart` and the barrel are
EN-only gap-audit files. Translate only comment/doc tokens mechanically. Review
the PT branch-name placeholder in `worktree_create_dialog.dart` as UI copy;
do not alter validation, callback values, branch rules, or dialog behavior.

## Documentation unit

Audit every exported widget with 3+ constructor parameters. Existing docs on
navigation/workspace widgets generally satisfy the Recommended tier and should
be translated while preserving intent. Do not add docs to the `widgets.dart`
barrel, private widget implementation classes, Flutter overrides, obvious
fields, or trivial `UpdateCard` surface.

## Acceptance criteria

- [ ] The 15 PT-bearing owned files contain EN-only comments/docs, and the
      reviewed placeholder is EN-first.
- [ ] Existing Recommended-tier docs remain meaningful after translation; any
      genuine gap found by the audit receives concise `///` intent docs.
- [ ] Dialog labels, validation/error results, callback contracts, navigation,
      pane/tab/worktree behavior, and signatures are otherwise unchanged.
- [ ] The barrel and other Skip-tier declarations do not receive filler docs.
- [ ] Changed files are formatted and pass the relevant analyzer check.

## Verification

From `cockpit/`:

```bash
export PUB_CACHE=~/projects/remote_pi/.pub-cache
../.tools/flutter/bin/flutter pub get --offline
../.tools/flutter/bin/flutter analyze
../.tools/flutter/bin/dart format --output=none --set-exit-if-changed \
  lib/app/cockpit/ui/widgets/agent_edit_dialog.dart \
  lib/app/cockpit/ui/widgets/cockpit_topbar.dart \
  lib/app/cockpit/ui/widgets/confirm_dialog.dart \
  lib/app/cockpit/ui/widgets/empty_pane.dart \
  lib/app/cockpit/ui/widgets/file_tree_panel.dart \
  lib/app/cockpit/ui/widgets/history_dialog.dart \
  lib/app/cockpit/ui/widgets/model_picker.dart \
  lib/app/cockpit/ui/widgets/pane_divider.dart \
  lib/app/cockpit/ui/widgets/pane_view.dart \
  lib/app/cockpit/ui/widgets/projects_rail.dart \
  lib/app/cockpit/ui/widgets/subfolder_dialog.dart \
  lib/app/cockpit/ui/widgets/update_card.dart \
  lib/app/cockpit/ui/widgets/welcome_view.dart \
  lib/app/cockpit/ui/widgets/widgets.dart \
  lib/app/cockpit/ui/widgets/workspace_avatar.dart \
  lib/app/cockpit/ui/widgets/workspace_settings_dialog.dart \
  lib/app/cockpit/ui/widgets/worktree_create_dialog.dart
```

Review the word diff and every changed literal. The full cockpit test suite is
the integrated parent gate.

## Implementation notes

- Files changed: the 15 PT-bearing widget files in scope (`agent_edit_dialog.dart`,
  `cockpit_topbar.dart`, `confirm_dialog.dart`, `empty_pane.dart`,
  `file_tree_panel.dart`, `history_dialog.dart`, `model_picker.dart`,
  `pane_divider.dart`, `pane_view.dart`, `projects_rail.dart`,
  `subfolder_dialog.dart`, `welcome_view.dart`, `workspace_avatar.dart`,
  `workspace_settings_dialog.dart`, and `worktree_create_dialog.dart`).
  `update_card.dart` and `widgets.dart` were audited and intentionally left
  unchanged as Skip-tier surfaces.
- Tests added: none; this is a comment/dartdoc and reviewed-copy change with no
  behavior change.
- Discrepancies from design: none. The PT branch placeholder was deliberately
  changed from `feat/minha-feature` to `feat/my-feature`; all other literals,
  identifiers, callbacks, validation, and navigation behavior were preserved.
- Documentation audit: all exported widgets with 3+ constructor parameters and
  exported dialog helpers in this shard retain concise EN intent/contract docs;
  no filler docs were added to private implementation widgets, overrides, the
  barrel, or `UpdateCard`.
- Adjacent issues parked: none.

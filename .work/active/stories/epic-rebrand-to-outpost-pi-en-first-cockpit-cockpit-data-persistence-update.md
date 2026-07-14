---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data-persistence-update
kind: story
stage: implementing
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-cockpit-data
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Translate cockpit data persistence and update adapters

## Scope

Translate Portuguese comment/dartdoc prose to idiomatic English in exactly
these files:

- `cockpit/lib/app/cockpit/data/repositories/hive_dismissed_update_store.dart`
- `cockpit/lib/app/cockpit/data/repositories/hive_project_repository.dart`
- `cockpit/lib/app/cockpit/data/repositories/hive_workspace_layout_store.dart`
- `cockpit/lib/app/cockpit/data/update/auto_updater_self_updater.dart`
- `cockpit/lib/app/cockpit/data/update/noop_self_updater.dart`
- `cockpit/lib/app/cockpit/data/update/update_checker_impl.dart`
- `cockpit/lib/app/cockpit/data/update/url_opener_impl.dart`

Preserve Hive keys and serialized shapes, manual project ordering and legacy
fallbacks, layout corruption behavior, updater state/lifecycle, appcast and
scheduled-check behavior, manifest fetch/parser failures, and URI validation.
Production changes are comment-only.

`hive_workspace_layout_store.dart` and `url_opener_impl.dart` contain
ASCII-only Portuguese missed by the original accent baseline and are
intentionally included. Repository implementations that merely satisfy a
documented domain port are Skip-tier for method-level gap-fill; retain and
translate only their adapter-specific class docs rather than restating the
contract.

## Acceptance criteria

- [ ] All seven files contain natural English adapter prose.
- [ ] Every public adapter class retains meaningful `///` documentation.
- [ ] Hive box names/keys, JSON shapes, update phases, URLs, plugin calls,
      timeout values, runtime strings, signatures, and behavior are unchanged.
- [ ] No redundant method docs are added to repository overrides.
- [ ] Normal and word-diff review shows production edits are comment-only;
      touched Dart files are formatted.
- [ ] The integrated feature can pass `flutter analyze` and `flutter test` from
      `cockpit/`.

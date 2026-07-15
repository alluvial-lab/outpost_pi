---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-settings-ui-review
kind: story
stage: review
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-settings
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Translate settings UI docs and review runtime copy

## Scope

Translate Portuguese comment/dartdoc prose in these 13 owned files:

- `cockpit/lib/app/settings/ui/categories/appearance_settings_panel.dart`
- `cockpit/lib/app/settings/ui/categories/connectivity_settings_panel.dart`
- `cockpit/lib/app/settings/ui/categories/language_settings_panel.dart`
- `cockpit/lib/app/settings/ui/categories/notification_settings_panel.dart`
- `cockpit/lib/app/settings/ui/connectivity_viewmodel.dart`
- `cockpit/lib/app/settings/ui/cron_viewmodel.dart`
- `cockpit/lib/app/settings/ui/daemons_viewmodel.dart`
- `cockpit/lib/app/settings/ui/notifications_viewmodel.dart`
- `cockpit/lib/app/settings/ui/pairing_controller.dart`
- `cockpit/lib/app/settings/ui/pairing_dialog.dart`
- `cockpit/lib/app/settings/ui/revoke_controller.dart`
- `cockpit/lib/app/settings/ui/revoke_dialog.dart`
- `cockpit/lib/app/settings/ui/settings_env_gate.dart`

Use bounded replacements only inside comments. Separately review every
human-readable literal in the four panels, connectivity/daemon ViewModels, and
pairing/revoke dialogs. The design baseline found those literals already
English; leave them unchanged unless PT is verified. Preserve commands, paths,
URLs, QR payloads, enum values, interpolation, and identifiers.

## Dartdoc gap-fill

Add meaningful `///` docs to these audited Always-tier exports:

- `CronLoad`; `CronViewModel.reload`, `setEnabled`, `remove`, `run`.
- `DaemonsLoad`; `DaemonsViewModel.start`, `stop`, `restart`, `remove`,
  `startAll`, `stopAll`, `restartAll`.
- `ConnectivityViewModel.loadRelay`, `loadDevices`.
- `PairingController.start`, `retry`.
- `RevokeController.run`.

Document intent, busy/error/reload behavior, ephemeral-gateway replacement,
and lifecycle/late-notification semantics. Do not gap-fill trivial getters,
fields, simple exported widgets, private helpers, or Flutter overrides.

## Acceptance criteria

- [x] All 13 files contain EN-only comment/dartdoc prose.
- [x] Every human-readable string literal in the named review surface is
      inspected separately from comment translation; already-English copy is
      not churned.
- [x] The eighteen named Always-tier declarations have meaningful `///` docs.
- [x] Pairing/revoke resources, subscriptions, `_disposed` guards, and mounted
      guards retain their current ownership and behavior.
- [x] The five `cockpit/test/settings/*.dart` files remain unchanged and pass.
- [x] Scoped PT/string review, dart format check, `flutter analyze`, and full
      `flutter test` pass at integration.

## Implementation notes

- Files changed: all 13 owned settings UI files listed in Scope.
- Tests added: none; this was a comment/dartdoc-only change, and the five
  existing `cockpit/test/settings/*.dart` files remained unchanged.
- Runtime-copy review: inspected the human-readable literals in the four panels,
  connectivity/daemon ViewModels, and pairing/revoke dialogs; all were already
  English, so no executable string literal changed.
- Dartdoc gap-fill: documented all eighteen named ViewModel/controller exports,
  including busy/error/reload behavior, ephemeral pairing-session replacement,
  and late-notification suppression after disposal.
- Rationale: two inherited PT comments were stale (one misdescribed
  `_SyntaxPreview`, and one was orphaned at end of file); corrected or removed
  them rather than preserve inaccurate documentation.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Verification: scoped accent and PT-term greps returned no Portuguese prose;
  `dart format --output=none --set-exit-if-changed` passed for all 13 files;
  `flutter analyze` reported no issues; full `flutter test` passed (241 tests).

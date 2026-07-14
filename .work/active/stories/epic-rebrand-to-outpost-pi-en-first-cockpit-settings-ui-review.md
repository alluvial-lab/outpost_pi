---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-settings-ui-review
kind: story
stage: implementing
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

- [ ] All 13 files contain EN-only comment/dartdoc prose.
- [ ] Every human-readable string literal in the named review surface is
      inspected separately from comment translation; already-English copy is
      not churned.
- [ ] The eighteen named Always-tier declarations have meaningful `///` docs.
- [ ] Pairing/revoke resources, subscriptions, `_disposed` guards, and mounted
      guards retain their current ownership and behavior.
- [ ] The five `cockpit/test/settings/*.dart` files remain unchanged and pass.
- [ ] Scoped PT/string review, dart format check, `flutter analyze`, and full
      `flutter test` pass at integration.

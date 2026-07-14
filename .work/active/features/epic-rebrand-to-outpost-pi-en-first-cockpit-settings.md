---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-settings
kind: feature
stage: drafting
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# EN-first + dartdoc gap-fill — cockpit settings module

## Brief

Translate Portuguese → English and adopt the dartdoc documentation framework
in the cockpit `settings` module (`cockpit/lib/app/settings/`): daemon
supervisor client, relay gateway, pairing/connectivity/cron/notifications
viewmodels and panels. 25 PT-bearing Dart files: `settings/ui` (13),
`settings/domain` (8), `settings/data` (3), plus `settings_module.dart`.

PT is predominantly comment prose, but this module holds user-facing settings
panels (connectivity, language, notifications, appearance) — a subset of the
~18 cockpit-wide PT string literals live here and need translation-review, not
mechanical sed. Gap-fill scope is the Always tier: ViewModel exports,
service-layer functions (supervisor client, relay gateway), `Result`-returning
functions.

## Epic context
- Parent epic: `epic-rebrand-to-outpost-pi-en-first`
- Position in epic: independent mid-size slice. No `depends_on` — the
  cockpit's wire-stable identifiers already migrated in the first rebrand
  epic. Can run in parallel with every other child feature. Shares the
  cockpit build gate with the other cockpit features, but the file set is
  disjoint (separate flutter_modular module).

## Foundation references
- `.agents/skills/documentation-conventions/SKILL.md` — dartdoc `///` format
  and the Always tier for Dart (ViewModel exports, service-layer functions).
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — cockpit code reference.
- `.agents/skills/scan-documentation/SKILL.md` — gate self-check.
- Parent epic `## Decomposition risks` — "user-visible UI text needs review"
  applies to the settings panels.

## What this feature does NOT cover
- Wire-stable identifiers (control-RPC discriminator) — owned by the first
  rebrand epic, already shipped.
- Product-identity string renames — owned by the mechanical-rename feature.
- `scripts/` shell comments — out of scope.
- Generated/vendored state.

## Verification
```bash
# from cockpit/
flutter analyze && flutter test
```
Plus a grep confirming zero PT (accented Latin) in `cockpit/lib/app/settings/`.

<!-- The design pass (`/agile-workflow:feature-design`) will fill in the
ViewModel/service export audit, the comment-vs-UI-string split, and the
gap-fill list. -->

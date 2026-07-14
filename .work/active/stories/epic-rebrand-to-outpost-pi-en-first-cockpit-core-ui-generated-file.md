---
id: epic-rebrand-to-outpost-pi-en-first-cockpit-core-ui-generated-file
kind: story
stage: implementing
tags: [rebrand, docs, i18n, cockpit]
parent: epic-rebrand-to-outpost-pi-en-first-cockpit-core
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Translate cockpit core UI prose and generated file header

Translate Portuguese prose in shared core UI files, add EN dartdoc to the one
named Always-tier gap, and handle the generated icon-map header as a tightly
bounded exception. Preserve theme tokens, rendering, widget signatures,
settings behavior, icon mappings, and generated constants.

## Owned files (17)

- `cockpit/lib/app/core/ui/file_icons/file_icon.dart`
- `cockpit/lib/app/core/ui/file_icons/file_icon_map.g.dart`
- `cockpit/lib/app/core/ui/file_icons/file_icons.dart`
- `cockpit/lib/app/core/ui/settings_controller.dart`
- `cockpit/lib/app/core/ui/themes/app_colors.dart`
- `cockpit/lib/app/core/ui/themes/app_theme.dart`
- `cockpit/lib/app/core/ui/themes/app_typography.dart`
- `cockpit/lib/app/core/ui/themes/cockpit_theme.dart`
- `cockpit/lib/app/core/ui/themes/syntax_colors.dart`
- `cockpit/lib/app/core/ui/themes/terminal_theme.dart`
- `cockpit/lib/app/core/ui/themes/theme_extensions.dart`
- `cockpit/lib/app/core/ui/widgets/app_menu.dart`
- `cockpit/lib/app/core/ui/widgets/code_editing_controller.dart`
- `cockpit/lib/app/core/ui/widgets/code_highlight.dart`
- `cockpit/lib/app/core/ui/widgets/hover_tap.dart`
- `cockpit/lib/app/core/ui/widgets/macos_notification_instructions_dialog.dart`
- `cockpit/lib/app/core/ui/widgets/window_controls.dart`

`cockpit/lib/app/core/ui/themes/themes.dart` is excluded: it is a Skip-tier
barrel with no Portuguese.

## Gap-fill inventory

Add one intent-level `///` contract to `AppThemeX` in
`ui/themes/theme_extensions.dart`, explaining shared theme-token access and its
fallback outside the installed `CockpitTheme` tree. Do not add redundant docs
to each obvious getter. `SettingsController` already has a meaningful exported
controller contract; translate it without documenting every setter.

## Generated-file exception

In `ui/file_icons/file_icon_map.g.dart`:

- edit only the leading PT header before `// ignore_for_file:`;
- retain the generated warning, attribution URL, source version, MIT license,
  regeneration warning, and default/dark variant meaning in English;
- add no dartdoc to generated constants/maps;
- do not format or reorder the generated body;
- verify every line after `// ignore_for_file:` remains unchanged.

The generator script is excluded by the parent epic, so this is an intentional
one-time shipped-file header edit.

## Runtime-string review

Translate the human-readable PT assertion in `cockpit_theme.dart` while keeping
the assertion condition and failure semantics unchanged. Do not alter theme
identifiers, token names, icon names, colors, typography, or widget behavior.

## Acceptance criteria

- [ ] The 17 owned files contain no Portuguese prose or human-readable PT
      assertion text.
- [ ] `AppThemeX` has meaningful EN `///` dartdoc with no redundant getter docs.
- [ ] `file_icon_map.g.dart` differs only in its header; generated constants and
      maps are identical.
- [ ] No docs are added to generated code, barrel exports, trivial helpers, or
      Flutter `build()` overrides.
- [ ] Themes, widgets, settings, and icon lookup behavior remain unchanged;
      `cockpit/test/widget_test.dart` passes after integration.

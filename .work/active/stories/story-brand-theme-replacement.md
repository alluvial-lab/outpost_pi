---
id: story-brand-theme-replacement
kind: story
stage: drafting
tags: [branding, app, cockpit]
parent: feature-public-flip-branding-and-exposure
depends_on: [story-brand-icon-regen-sweep]
release_binding: null
gate_origin: null
created: 2026-08-14
updated: 2026-08-14
---

# App + cockpit theme replacement — Phosphor Beacon

Replace upstream-derived UI colors with the locked identity (tokens.css is
the contract; Dart constants mirror it — single source per
`.agents/rules/code-design.md`).

1. **app** `lib/ui/core/themes/app_colors.dart` — currently BYTE-IDENTICAL to
   upstream (audit item 2). Port Phosphor Beacon: dark-native ramp
   (#0D1210/#131A16/#1E2620, text #E4EFE8/#89978D), accent #74CC9C (dark) /
   #256E47 (light), status set, on-accent inks. Keep existing semantic names
   so call sites don't churn; update theme_extensions.dart wiring if needed.
2. **cockpit** `lib/app/core/ui/themes/app_colors.dart` — converges on the
   same ramp (currently divergent upstream palette). Terminal/syntax themes
   stay functional (terminal_theme/syntax_colors); align their green family
   with the phosphor accent where it doesn't hurt readability.
3. **Space Mono everywhere** via existing `google_fonts` dep (both apps):
   display/body/mono = SpaceMono; drop the vestigial commented Schyler/Trajan
   stanzas from both pubspecs (audit item 6).
4. Light mode: follow each app's existing mechanism; tokens.css light values
   are the reference.

Verify: `flutter analyze` + `flutter test --exclude-tags e2e` (app),
`flutter analyze` + `flutter test` (cockpit); visual smoke of pairing +
session screens in both modes.

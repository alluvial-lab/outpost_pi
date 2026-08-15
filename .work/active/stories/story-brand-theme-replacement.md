---
id: story-brand-theme-replacement
kind: story
stage: done
tags: [branding, app, cockpit]
parent: feature-public-flip-branding-and-exposure
depends_on: [story-brand-icon-regen-sweep]
release_binding: null
gate_origin: null
created: 2026-08-14
updated: 2026-08-15
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

## Implementation run

- Dependency `story-brand-icon-regen-sweep` is `done` with green asset/hash
  evidence (`56bcbcd`).
- Ownership: cohesive host implementation across the two Flutter theme roots;
  semantic token names stay stable and platform call sites remain untouched.
- Capability: `openai-codex/gpt-5.6-sol`, high (caller-selected for the
  cross-file theme-contract port).

## Implementation notes

- Replaced mobile and Cockpit dark/light semantic registries with the locked
  Phosphor Beacon neutral, accent, on-accent, and status ramps while preserving
  existing call-site token names.
- Switched display/body/label/code/wordmark roles to Space Mono through the
  existing `google_fonts` dependency. Mobile's direct `kMonoFamily` sites use
  google_fonts' registered `SpaceMono_regular` family; Cockpit requests the
  700 variant for display roles and regular for body/code.
- Kept Cockpit terminal and syntax palettes functional: terminal surfaces,
  cursor/selection, ANSI green/status family, and readable blue/status roles
  now follow the identity; syntax families retain their distinguishing hues
  with only readable green roles aligned.
- Removed inherited Schyler/Trajan example stanzas and refreshed stale font
  comments in both pubspecs.
- Added focused contract tests in both apps for exact dark/light palette values,
  Space Mono resolution, and Cockpit terminal/syntax alignment.

## Verification evidence

- `cd app && flutter analyze --no-pub` — PASS, no issues.
- `cd app && flutter test --no-pub --exclude-tags e2e --concurrency=1` —
  PASS, 874 tests. The prescribed `--concurrency=2` run reached 870 passes but
  exposed the same unrelated suite-isolation failure twice in
  `sync_service_test.dart` (`server error clears pending chunk flush...`,
  expected idle event but saw null); that test passes alone (1/1). No sync code
  is in this story, so it was not changed or hidden, and the caller forbids
  touching unrelated queue items.
- `cd cockpit && flutter analyze --no-pub` — PASS, no issues.
- `cd cockpit && flutter test --no-pub --concurrency=2` — PASS, 280 tests.
- Focused new theme tests — PASS, 3 mobile + 3 Cockpit.
- Grep for Schyler/Trajan and prior font calls/palette anchors — zero matches.
- `git diff --check` — PASS.
- Visual device smoke is not available on this Linux VM (no phone and no
  macOS/Windows desktop target). Exact dual-mode token tests are the automated
  substitute; on-device visual smoke remains a release/UAT step.

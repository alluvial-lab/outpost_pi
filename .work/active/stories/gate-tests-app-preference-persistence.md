---
kind: story
release_binding: null
parent: feature-cockpit-settings-control-tests
stage: done
id: gate-tests-app-preference-persistence
tags: [testing]
depends_on: []
gate_origin: testing
created: 2026-07-01
updated: 2026-07-18
---

# App-preference panels only have importability coverage, not persistence/controller behavior

## Location
cockpit/lib/app/settings/ui/categories/appearance_settings_panel.dart:16

## Issue
AC uncovered: SettingsController remains the only owner of AppSettings persistence; no panel writes Hive directly. (bound item: epic-bold-cockpit-workspace-projection-settings-split)

## Recommendation
Strengthen test/settings/app_preferences_settings_panel_test.dart to pump appearance/language/notification panels with a memory SettingsStore, interact with controls, and assert settings are saved through SettingsController.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected; bounded widget/controller test work).
- Review weight: `standard` (caller default); review is feature-level because this is a child checkpoint.
- Files changed: `cockpit/test/settings/app_preferences_settings_panel_test.dart`.
- Tests added/removed: added appearance font/conversation persistence, notification-toggle persistence, and format-on-save persistence; removed the importability-only panel assertion. Existing language normalization/reset and notification lifecycle tests remain.
- Simplification: consolidated appearance and notification panels onto one Modular/Shadcn pump helper.
- Verification: `PUB_CACHE=/home/agent/projects/outpost_pi/.pub-cache flutter test --no-pub test/settings/app_preferences_settings_panel_test.dart` — 9 tests passed.
- Discrepancies from design: the story frontmatter remained at `drafting` despite the delegated caller identifying it as `implementing`; completed evidence advanced it directly to `done`.
- Adjacent issues parked: none.

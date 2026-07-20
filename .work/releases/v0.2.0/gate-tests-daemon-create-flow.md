---
kind: story
release_binding: v0.2.0
parent: feature-cockpit-settings-control-tests
stage: done
id: gate-tests-daemon-create-flow
tags: [testing]
depends_on: []
gate_origin: testing
created: 2026-07-01
updated: 2026-07-20
---

# Daemon tests cover rename/cancel but not successful create flow

## Location
cockpit/lib/app/settings/ui/categories/daemon_settings_panel.dart:40

## Issue
AC uncovered: Create, rename, start/stop/restart, fleet actions, supervisor restart, and remove call the same DaemonsViewModel methods as before. (bound item: epic-bold-cockpit-workspace-projection-settings-split)

## Recommendation
Add a successful create-path test for DaemonSettingsPanel/DaemonEditorDialog that supplies a chosen folder and asserts DaemonsViewModel.create(cwd, name: ...) is called.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected; bounded widget-test addition at an existing public seam).
- Review weight: `standard` (caller override); review is feature-level because this is a child checkpoint.
- Files changed: `cockpit/test/settings/daemon_settings_panel_test.dart`.
- Tests added/removed: added a successful create journey that drives the real dialog, enters a whitespace-padded name, chooses `/work/new-agent` through a `FilePicker` test implementation, and asserts exactly one `create('/work/new-agent', name: 'Build agent')` call. Existing rename, cancel, action, reload, and timer tests remain.
- Simplification: reused the existing panel pump and recording ViewModel; no production hook or shared test-support abstraction was added.
- Verification: focused file passed 8 tests; full `PUB_CACHE=/home/agent/projects/outpost_pi/.pub-cache flutter test --no-pub` passed 257 tests, versus a green 256-test baseline. `flutter analyze --no-pub` reported only two unrelated pre-existing/concurrent info diagnostics and no issue in the changed test.
- Discrepancies from design: the test binding left `FilePicker.platform` uninitialized, so the test registers the package's host default before replacing and restoring the singleton; this preserves the designed public seam and cleanup contract.
- Adjacent issues parked: none.

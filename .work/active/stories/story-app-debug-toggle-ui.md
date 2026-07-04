---
id: story-app-debug-toggle-ui
kind: story
stage: implementing
tags: [app, observability, ui]
parent: feature-cross-side-observability
depends_on:
  - story-app-debug-log-adapter
release_binding: null
gate_origin: null
created: 2026-07-04
updated: 2026-07-04
---

# App debug log: app-global debug toggle + export/clear UI

## Scope (Unit 3 of `feature-cross-side-observability`)

The operator-facing surface: an app-level "Debug logging" switch in Settings
that gates capture, plus Export and Clear actions. The toggle is app-global
(not per-session); one ring accumulates across peers/sessions until cleared
or capped.

### Changes
- **`Preferences`**: add `debugLogging` (bool, default false), persisted.
- **`dependencies.dart`**: register `DebugLogImpl` via `addService` (the
  disposing path — review C3) so `disposeDependencies()` flushes on teardown.
  Wire the debug-enabled callback to `prefs.debugLogging`.
- **`SettingsViewModel`**: add `isDebugLogging` / `setDebugLogging(bool)` /
  `exportDebugLog()` / `clearDebugLog()`.
- **`settings_page.dart`**: add a `_DebugSection` with:
  - **Debug logging** switch (on/off).
  - **Export debug log** → `share_plus` share sheet (jsonl file).
  - **Clear debug log** → confirm dialog, then `clear()`.
- **`pubspec.yaml`**: add `path_provider` (adapter) + `share_plus` (export).

## Acceptance criteria

- [ ] Toggle persists across restarts in `Preferences`.
- [ ] When OFF, `DebugLogImpl.log()` is a no-op (no serialization, no file I/O).
- [ ] When ON, capture flows; the ring accumulates across sessions.
- [ ] "Export debug log" opens the share sheet with the jsonl file.
- [ ] Export disabled / shows "no log yet" when `export()` returns null.
- [ ] "Clear debug log" confirms then wipes ring + file.
- [ ] `disposeDependencies()` flushes pending lines (lifecycle test).
- [ ] `flutter analyze` clean; `flutter test` green (new UI + toggle tests).

## Out of scope

- The adapter itself (story-app-debug-log-adapter).
- Capture-site routing (story-app-capture-routing).

## References

- Parent: `feature-cross-side-observability.md` (Unit 3).
- `app/lib/data/preferences/preferences.dart` — persisted prefs pattern.
- `app/lib/config/dependencies.dart` — `addService` disposing registration.
- `app/lib/ui/settings/settings_page.dart` — section pattern (`_RelaySection`, `_DisplaySection`).

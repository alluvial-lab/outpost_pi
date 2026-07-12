---
id: story-app-debug-toggle-ui
kind: story
stage: done
review_addressed: 2026-07-05
tags: [app, observability, ui]
parent: feature-cross-side-observability
depends_on:
  - story-app-debug-log-adapter
release_binding: v0.1.0
gate_origin: null
created: 2026-07-04
updated: 2026-07-05
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
- [ ] Toggling OFF preserves existing ring/file (only new capture is gated —
      review v2 #5).
- [ ] Export + Clear work while debug logging is OFF (read/wipe whatever is on disk).
- [ ] Clear wipes ring + file but NOT `Preferences.debugLogging`.
- [ ] "Export debug log" opens the share sheet with the jsonl file.
- [ ] Export disabled / shows "no log yet" when `export()` returns null.
- [ ] UI warns exports may include truncated message previews + diagnostic IDs
      (review v2 #5 — operator-chosen destinations, but not self-enforcing).
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

## Implementation notes

- `app/lib/data/preferences/preferences.dart`: added persisted `debugLogging` with default `false`, `prefs.debug_logging` storage, load hydration, setter, and notifications.
- `app/lib/config/dependencies.dart`: registered `DebugLogImpl` through `addService<DebugLog>` with `debugEnabled: () => prefs.debugLogging`, and injected `DebugLog` into `SettingsViewModel`.
- `app/lib/ui/settings/viewmodels/settings_viewmodel.dart`: added `isDebugLogging`, `setDebugLogging`, `exportDebugLog`, and `clearDebugLog` delegates.
- `app/lib/ui/settings/settings_page.dart`: added `_DebugSection` with toggle, jsonl export share-sheet action, clear confirmation, mounted guards, and export privacy warning.
- `app/pubspec.yaml` / `app/pubspec.lock`: added `share_plus`; `path_provider` was already present.
- Tests added/extended:
  - `app/test/data/preferences/preferences_test.dart`: debug toggle default + persistence.
  - `app/test/ui/settings/settings_viewmodel_test.dart`: toggle persistence and DebugLog export/clear delegation without clearing the toggle.
  - `app/test/ui/settings/settings_page_test.dart`: UI toggle persistence, export share callback, no-log feedback, and clear confirmation preserving the toggle.
  - `app/test/data/debug/debug_log_impl_test.dart`: Preferences callback gating and `disposeDependencies()`/`addService` lifecycle flush coverage.

Verification from `app/`:

```text
flutter test
00:25 +655: All tests passed!
```

```text
flutter analyze
Analyzing app...

   info • 'axisAlignment' is deprecated and shouldn't be used. Use alignment instead. This property provides full control over both axes, which is an improvement over the old axisAlignment. This feature was deprecated after v3.41.0-1.0.pre. Try replacing the use of the deprecated member with the replacement • lib/ui/chat/widgets/input_bar.dart:802:7 • deprecated_member_use

1 issue found. (ran in 3.5s)
```

Deviation: `flutter analyze` exits non-zero because of the documented pre-existing `axisAlignment` info in `app/CLAUDE.md`; `input_bar.dart` explicitly says not to change it without a Flutter pin bump, so this story left it untouched.

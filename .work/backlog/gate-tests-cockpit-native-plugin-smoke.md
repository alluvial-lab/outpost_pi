---
id: gate-tests-cockpit-native-plugin-smoke
created: 2026-08-15
updated: 2026-08-15
tags: [cockpit, testing]
---

# Cockpit native-plugin major upgrades have no runtime seam smoke

Post-hoc v0.5.0 tests-gate finding. Severity: Medium.

## Location
v0.5.0 bumped `window_manager` (`cockpit/pubspec.yaml:71`),
`media_kit_video` (`:87`), `pasteboard` (`:99`), `desktop_drop` (`:104`).
No cockpit test references `MediaView`, `DropTarget`, `Pasteboard`, or
`windowManager`; media coverage stops at path classification
(`cockpit/test/data/file_reader_impl_test.dart:10-11`); CI runs analyze +
unit only (`.github/workflows/ci.yml:168-188`).

## Work
Bounded desktop integration smoke on release platforms: launch/manipulate the
window, open+dispose a short local media fixture, inject a native drop/paste,
open/close a terminal. Avoid mock-only plugin tests — they would not protect
the upgraded native boundary.

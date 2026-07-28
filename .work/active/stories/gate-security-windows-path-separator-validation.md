---
id: gate-security-windows-path-separator-validation
kind: story
stage: done
tags: [security, pi-extension]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-01
updated: 2026-07-28
---

# File name validation misses Windows path separators

## Location
cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart:532

## Issue
File/folder create and rename validation rejects / but not \, so Windows names such as ..\target can escape the intended directory when joined into a path.

## Implementation notes

- Added `cockpit/lib/app/cockpit/domain/validators/file_name_validator.dart` to reject `/`, `\\`, drive/UNC indicators, and control characters; normalize the final child path and verify it remains inside the normalized parent.
- Updated `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart` so file/folder creation and rename use the shared validator, including Windows parent separators.
- Added `cockpit/test/domain/file_name_validator_test.dart` covering Windows separators, drive/UNC paths, control characters, and normalized containment.
- Verification: `flutter analyze` clean; `flutter test` green (273 tests passed).

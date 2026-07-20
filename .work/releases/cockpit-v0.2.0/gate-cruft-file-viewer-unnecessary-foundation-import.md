---
id: gate-cruft-file-viewer-unnecessary-foundation-import
kind: story
stage: done
tags: [cockpit, cleanup]
parent: null
depends_on: []
release_binding: cockpit-v0.2.0
gate_origin: cruft
created: 2026-07-20
updated: 2026-07-20
---

# Remove redundant Flutter foundation import from FileViewer

## Confidence
High

## Severity
High

## Category
unused import

## Location
`cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart:19`

## Evidence
```text
flutter analyze --no-pub lib/app/cockpit/ui/session/agent_session.dart lib/app/cockpit/ui/viewmodels/workspace_projection.dart lib/app/cockpit/ui/widgets/file_viewer.dart test/ui/workspace_projection_test.dart

info • The import of 'package:flutter/foundation.dart' is unnecessary because all of the used elements are also provided by the import of 'package:shadcn_flutter/shadcn_flutter.dart'. • lib/app/cockpit/ui/widgets/file_viewer.dart:19:8 • unnecessary_import
```

## Removal
Remove `package:flutter/foundation.dart`; `debugPrint` remains available through the existing `shadcn_flutter` import.

## Gate execution
The cruft scanner ran inline at the operator's instruction, so this finding has reduced fresh-context isolation.

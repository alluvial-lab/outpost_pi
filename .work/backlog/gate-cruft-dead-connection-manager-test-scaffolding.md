---
id: gate-cruft-dead-connection-manager-test-scaffolding
gate_origin: cruft
created: 2026-08-28
updated: 2026-08-28
tags: [cleanup, app, testing]
---

# Remove dead ConnectionManager test scaffolding

## Confidence
Medium

## Category
dead test scaffolding / unused-import suppression

## Location
`app/test/transport/connection_manager_working_test.dart:7,69-71`; adjacent
`app/test/transport/connection_manager_thinking_test.dart:6,63-69`

## Evidence
```dart
import 'dart:typed_data';

// Avoid analyzer "unused" on the import.
// ignore: unused_element
Uint8List _placeholder() => Uint8List(0);
```

The working test's `_placeholder` has no call sites. The adjacent thinking test
has the same unused import/placeholder and additionally marks `pushServer` as
unused even though it has no call sites. The working test's `pushServer` is
live, so it must remain there.

## Removal
Remove the unused `dart:typed_data` imports and `_placeholder` helpers from
both tests. Remove the unused `pushServer` helper and its suppression from the
thinking test only; preserve the working test's live `pushServer` helper and
all control-stream test behavior.

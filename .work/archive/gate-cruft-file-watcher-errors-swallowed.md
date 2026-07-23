---
id: gate-cruft-file-watcher-errors-swallowed
release_binding: null
gate_origin: cruft
created: 2026-07-20
updated: 2026-07-20
tags: [cockpit, cleanup]
---

# Make file-watcher failures observable

## Confidence
Medium

## Severity
Medium

## Category
empty catch

## Location
`cockpit/lib/app/cockpit/ui/viewmodels/workspace_projection.dart:457`

## Evidence
```dart
_fileWatchers[id] = _fileReader.watch(viewer.path).listen((_) {
  // reload handling
}, onError: (_) {});
```

The listener installs an error handler that discards every file-watch failure. The handler predates the release bundle (`3366c453`), so this is an ambient finding rather than release-blocking work.

## Removal
Replace the empty error handler with a deliberate, observable error path appropriate for file-watch failures, or omit it so the stream's normal error behavior is retained. Preserve the current reload/debounce lifecycle.

## Gate execution
The cruft scanner ran inline at the operator's instruction, so this finding has reduced fresh-context isolation.

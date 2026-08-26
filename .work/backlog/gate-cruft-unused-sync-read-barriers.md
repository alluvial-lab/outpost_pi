---
id: gate-cruft-unused-sync-read-barriers
gate_origin: cruft
created: 2026-08-26
updated: 2026-08-26
tags: [app, cleanup, testing]
---

# Remove the unused transcript-store read barrier seam

## Confidence
High

## Severity
Medium

## Relevance
Ambient: the stale seam is in a release-touched sync test harness, but it
cannot affect production behavior.

## Category
dead test scaffolding / superseded synchronization barrier

## Location
`app/test/data/sync/sync_service_test.dart:170-171,224-230`

## Evidence
```dart
Completer<void>? readGate;
Completer<void>? readStarted;

final gate = readGate;
if (gate != null) {
  readGate = null;
  final started = readStarted;
  if (started != null && !started.isCompleted) started.complete();
  await gate.future;
}
```

Call-site search finds no assignment to `_MemoryTranscriptStore.readGate` or
`readStarted`. The similarly named local completers at lines 4144-4148 and
5396-5400 are assigned to `_MemoryOwnerDeliveryOutbox.listGate` and
`listStarted`, not to this transcript-store seam. The only remaining uses are
the declaration and its unexercised internal branch.

## Removal
Delete `readGate` and `readStarted` from `_MemoryTranscriptStore` and remove the
unexercised gate branch in `readSession`. Keep `readCalls` and its assertions,
which still verify that duplicate hydration does not perform a read.

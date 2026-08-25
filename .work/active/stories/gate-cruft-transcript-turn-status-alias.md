---
id: gate-cruft-transcript-turn-status-alias
kind: story
stage: implementing
tags: [cleanup]
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: cruft
created: 2026-08-25
updated: 2026-08-25
---

# Remove the obsolete transcript turn-status compatibility alias

## Confidence
High

## Category
Compatibility shim / dead alias

## Relevance
Release-relevant: revealed by the F4 transcript projection rewrite.

## Location
`app/lib/domain/transcript/transcript_projection.dart:5-16`

## Evidence
```dart
/// Backward-compatible aliases for the transcript seam.
abstract final class TranscriptTurnStatus {
  static const idle = AppTurnStatus.idle;
  static const working = AppTurnStatus.working;
  static const awaitingTool = AppTurnStatus.awaitingTool;
  static const streaming = AppTurnStatus.streaming;
  static const done = AppTurnStatus.done;
  static const error = AppTurnStatus.error;
  static const stale = AppTurnStatus.stale;
}
```

The repository's only callers are transcript tests; production code already uses `AppTurnStatus` directly.

## Removal rationale
Delete the transitional alias and update the remaining test references to `AppTurnStatus`. The app is not a published Dart package, so retaining an internal alias for unseen external callers has no verified compatibility value.

## Risk
None to runtime behavior or persisted/wire contracts. The only required follow-up is mechanical test-symbol replacement.

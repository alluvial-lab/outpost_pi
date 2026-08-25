---
id: gate-cruft-transcript-turn-status-alias
kind: story
stage: done
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

## Implementation
- Proof: repository grep found the app alias declaration plus six app test references and no production caller; similarly named Pi-extension and Cockpit types are independent declarations.
- Removal: deleted `TranscriptTurnStatus` and mechanically changed the six transcript-projection assertions to canonical `AppTurnStatus` values.
- Verification: `flutter test test/domain/transcript/transcript_projection_test.dart` passed (24 tests). The release-wide app analyze and full non-E2E suite are recorded in the gate-fix completion report.
- Execution capability: sol/high; direct-read cleanup with compiler/test evidence.
- Adjacent issues parked: none.

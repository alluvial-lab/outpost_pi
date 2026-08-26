---
id: feature-cruft-consolidated-cleanup-step-1-app
kind: story
stage: done
tags: [refactor, cleanup, app]
parent: feature-cruft-consolidated-cleanup
depends_on: []
release_binding: v0.9.0
gate_origin: null
created: 2026-08-26
updated: 2026-08-26
---

# Consolidated cruft cleanup: app

## Scope

Implement the verified app-side cleanup findings from
`feature-cruft-consolidated-cleanup`. Keep the canonical turn projection as the
only app turn API and remove the empty EPK branch. The old
`TranscriptTurnStatus` alias finding is already gone; the import at
`transcript_projection.dart:7` is still required by the active streaming
behavior comparison and must remain.

## Current state

`app/lib/data/sync/sync_service.dart:300-307` still exposes three derived
compatibility getters:

```dart
bool get isWorking => turnProjection.working;
Stream<bool> get workingStream =>
    turnProjectionStream.map((projection) => projection.working).distinct();
String? get workingReplyTo => turnProjection.cancelTargetId;
```

The in-repository callers are test fixtures/assertions, not a published app
package API. The canonical `turnProjection` and `turnProjectionStream` remain
in use and provide the same values.

`app/lib/data/transport/epk_encoding.dart:30` still contains an empty branch:

```dart
final out = base64.encode(bytes);
if (out != b64) {
}
return out;
```

## Target state

- Remove the three compatibility getters and their compatibility comment.
- Migrate every in-repository `SyncService` caller without weakening an
  assertion:
  - `sync.turnProjection.working` replaces `sync.isWorking`.
  - `sync.turnProjection.cancelTargetId` replaces `sync.workingReplyTo`.
  - `sync.turnProjectionStream.map((projection) => projection.working).distinct()`
    replaces `sync.workingStream` when a boolean stream is required.
- Keep `turnProjection` and `turnProjectionStream` as the canonical public
  projection surface.
- Reduce `toStandardB64` to `final out = ...; return out;`, preserving all
  conversion, invalid-input, and empty-input behavior.

## Implementation notes

- Search both `app/lib/` and `app/test/` before editing so no old getter
  reference remains. The existing tests already assert the turn behavior and
  should be mechanically migrated, not deleted or broadened.
- Do not remove `transcript_projection.dart`'s `UserMessageStreamingBehavior`
  import: it is used by the reducer.
- Do not change relay URL settings projections; the `effectiveRelayUrl`
  compatibility finding was already implemented in v0.4.0.

## Acceptance criteria

- [x] `grep` finds no `isWorking`, `workingStream`, or `workingReplyTo`
      references on `SyncService` outside unrelated ViewModel/state symbols.
- [x] Existing turn-state and EPK tests retain their behavioral assertions.
- [x] `flutter analyze` passes, allowing only the documented unrelated
      `axisAlignment` info.
- [x] `flutter test --exclude-tags e2e` passes.
- [x] The resulting diff contains no changes outside `app/` and this story's
      implementation-owned app/test files.

## Implementation

Removed the three derived `SyncService` compatibility getters and migrated the
existing sync-service tests to the canonical `turnProjection` and
`turnProjectionStream` projections. The test assertions and stream distinctness
remain unchanged; only the access path changed. Removed the empty comparison
branch in `toStandardB64` without changing decoding, encoding, or fallback
behavior. The live `UserMessageStreamingBehavior` import remains because the
transcript reducer still uses it.

Verification: `flutter analyze` passed. The first full
`flutter test --exclude-tags e2e --concurrency=2` run had one transient
protocol-codegen comparison failure; the isolated codegen test passed, and an
immediate second full run passed with all tests green. The full runs emitted
the existing network font-load diagnostics from `google_fonts`, but the final
verification reported no failed test.

## Risk

Low to medium. The changes are internal and behavior-preserving, but the
compatibility getters have many test callers. A missed migration would be a
compile failure; changing a projection assertion would be test gaming.

## Rollback

Revert the single app cleanup commit. The old derived getters and empty branch
can be restored without touching persisted data, wire frames, or user-visible
state.

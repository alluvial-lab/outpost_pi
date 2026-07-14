---
id: epic-rebrand-to-outpost-pi-en-first-app-domain
kind: story
stage: implementing
tags: [rebrand, docs, i18n, app]
parent: epic-rebrand-to-outpost-pi-en-first-app
depends_on: []
release_binding: null
gate_origin: null
created: 2026-07-14
updated: 2026-07-14
---

# Translate app domain prose and fill Always-tier dartdoc

## Scope

Own `app/lib/domain/**` only. Translate the six PT-bearing files in this
boundary and add EN `///` comments to the reviewed Always-tier domain gaps.
Do not change behavior, imports, signatures, protocol shape, or persistence
shape.

PT-bearing files:

- `app/lib/domain/CLAUDE.md`
- `app/lib/domain/contracts/dismissed_update_store.dart`
- `app/lib/domain/contracts/update_checker.dart`
- `app/lib/domain/contracts/url_opener.dart`
- `app/lib/domain/entities/update_info.dart`
- `app/lib/domain/value_objects/semver.dart`

`update_info.dart` is the only literal-review file in this story: translate its
five Portuguese `FormatException` messages while preserving exception types and
validation branches. All other owned PT is comment/prose.

## Dartdoc gap manifest

Add intent/contract dartdoc to:

- `contracts/disposable.dart`: `Disposable`, `dispose`.
- `contracts/repository.dart`: `Repository`.
- `contracts/service.dart`: `Service`.
- `contracts/usecase.dart`: `UseCase`.
- `contracts/transcript_event_store.dart`: `TranscriptSessionKey`,
  `AppendTranscriptEventsResult`, `TranscriptEventStore`, `appendAll`,
  `readSession`, `watchSession`.
- `session_state.dart`: `ChatMessage`, `UserMsg`, `AssistantMsg`, `ToolEvent`,
  `StreamingMessage`, `AppTurnProjection`.
- `transcript/transcript_event.dart`: `TranscriptEvent` and all nine concrete
  event variants.
- `transcript/transcript_projection.dart`: `TranscriptTurnView`,
  `deriveChatTurnProjection`, `TranscriptProjection`.
- `value_objects/reachability.dart`: `ReachabilityStateLabel`,
  `reachabilityBackoffForAttempt`, `ReachabilityHeartbeat`,
  `ReachabilityTransition`.

Do not add a redundant comment to schema-shaped `UpdateArtifact`; it is Skip.
Do not document constructors/fields/trivial accessors merely because Dart makes
them public.

## Acceptance criteria

- [ ] All six PT-bearing files are natural EN and no PT runtime literal remains.
- [ ] Every declaration in the gap manifest has meaningful adjacent `///`
      intent/contract prose, not type restatement.
- [ ] The five `FormatException` branches preserve validation and exception
      behavior while exposing EN messages.
- [ ] No domain layer boundary or executable logic changes.
- [ ] Touched Dart files are formatted; relevant domain tests pass.
- [ ] The feature-level integrated run can pass `flutter analyze` and
      `flutter test` from `app/`.

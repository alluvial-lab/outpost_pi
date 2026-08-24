---
id: feature-app-edge-trigger-room-snapshot-consumers-opt-2
kind: story
stage: implementing
tags: [perf, app]
parent: feature-app-edge-trigger-room-snapshot-consumers
depends_on: [feature-app-edge-trigger-room-snapshot-consumers-opt-1]
release_binding: null
gate_origin: perf-design
created: 2026-08-24
updated: 2026-08-24
---

# Coalesce Chat/Home room-snapshot consumer work

## Brief

Route Chat and Home consumers through the shared semantic room-snapshot edge
created by `feature-app-edge-trigger-room-snapshot-consumers-opt-1`. Chat
currently starts `_handleRoomsChanged` and calls `_recompute` immediately, then
the serialized binding path can recompute again. Home consumes every accepted
canonical snapshot through a broad `HomeList` listener. Preserve one update for
genuine presentation/liveness/session changes, but delete binding/projection
work for metadata that cannot affect the consumer and all no-op work.

## Design

- `ChatViewModel` should bind only on session identity or transport/liveness
  edges. A same-session working/model update recomputes the turn projection
  once, with no binding attempt. A genuine binding edge recomputes once after
  the guarded bind, not both before and after it.
- `HomeViewModel` should consume the shared full snapshot/edge without creating
  a duplicate room map. It may skip an edge only when the Home presentation and
  selected-session reference cannot change. Keep `roomId` and `sessionId` in
  canonical state because Home's open-session route and tablet selection use
  them.
- If widget profiling identifies a broad rebuild after the ViewModel edge gate,
  narrow the relevant Home/Chat consumer with `context.select`; do not weaken
  the authoritative room snapshot or replace it with a cache.
- Keep `_MessageList` anchor behavior unchanged. Room-only metadata must not
  schedule post-frame anchor restoration; transcript identity/streaming changes
  must continue to do so.

## Benchmark checkpoint

Location: `app/test/perf/room_snapshot_consumers_benchmark_test.dart`.
Remove the design-only skip after the implementation adds explicit async
teardown. Compare 339-snapshot runs at 0/200/5,500 events and count full reads,
binding refreshes, `notifyListeners`, widget builds, and anchor callbacks.
Expected metadata/working movement after opt-1 is zero reads/binding calls;
working changes still produce one Chat/Home notification/build, while no-op
snapshots produce zero notifications/builds and zero anchor callbacks.

## Acceptance Criteria

- [ ] Same-session working/model updates do not refresh the Chat binding.
- [ ] Genuine session rotation rebinds once, rejects stale projection updates,
      and emits one coherent Chat state update.
- [ ] Home updates working, liveness, room metadata, room add/remove, and
      selected-session rotation exactly once; no-op edges do nothing.
- [ ] `working:false` converges in both Chat and Home after success, reconnect,
      room end, and session replacement.
- [ ] Room-only churn produces zero post-frame anchor callbacks; transcript
      changes preserve the existing anchor oracle.
- [ ] Relevant Chat/Home tests plus the bounded app suite pass.

## Likely files

- `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`
- `app/lib/ui/home/viewmodels/home_viewmodel.dart`
- `app/lib/ui/home/states/home_state.dart` (only if a typed projection is
  required)
- `app/lib/ui/chat/chat_page.dart` / `app/lib/ui/home/home_page.dart` (only if
  widget-level selectors are justified by the benchmark)
- `app/test/ui/chat/chat_viewmodel_test.dart`
- `app/test/ui/home/home_viewmodel_test.dart`
- `app/test/perf/room_snapshot_consumers_benchmark_test.dart`

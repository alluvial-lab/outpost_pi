---
id: feature-app-edge-trigger-room-snapshot-consumers-opt-2
kind: story
stage: done
tags: [perf, app]
parent: feature-app-edge-trigger-room-snapshot-consumers
depends_on: [feature-app-edge-trigger-room-snapshot-consumers-opt-1]
release_binding: v0.8.0
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

## Implementation

- Execution capability: `sol/high`; edge-routed Chat binding and Home/Chat
  presentation fan-out with semantic equality/no-op tests.
- Review weight: not applicable — child-story checkpoint.
- `ChatViewModel` now consumes the shared change stream, binds only for
  fresh-live/session edges, and recomputes synchronously once for same-session
  presentation changes. `HomeViewModel` applies only Home-visible changes from
  the same canonical snapshot.
- Same-session working/model churn performs **0 binding refreshes** (baseline
  **339**) while preserving **339/339** Chat/Home notifications and rebuild
  callbacks for 339 genuine alternating working edges. An equal/no-op snapshot
  produces **0** reads, bindings, notifications, rebuild callbacks, and anchor
  callbacks.
- Final host-side 339-snapshot wall p50/p95: **41/62 us** (0 events), **35/53
  us** (200), and **29/57 us** (5,500), versus the design baselines **0.882/1.498
  ms**, **0.715/1.364 ms**, and **0.753/1.639 ms** respectively. Fake-list
  traversal is not presented as encrypted-Hive latency.
- Session rotation binds Chat exactly once; `working:false` notifies Chat/Home
  exactly once and converges idle. The transcript-identity anchor oracle remains
  **0** for room-only churn.
- The sibling transcript-pipeline worker landed first. This story was rebased
  onto those commits; no projection/reducer internals were modified.

Verification: targeted Chat/Home/ConnectionManager/SyncService tests and the
benchmark pass; `flutter analyze` is clean and the full bounded app suite passes
with **937 tests** under `--exclude-tags e2e --concurrency=2`.

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

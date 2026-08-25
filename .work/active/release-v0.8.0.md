---
id: release-v0.8.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: v0.8.0
gate_origin: null
created: 2026-08-25
updated: 2026-08-25
---

# Release v0.8.0

Post-v0.7.0 arc: the v0.8.0 performance campaign (debug ring 102×,
projection pipeline 22×/43×, snapshot fan-out edge-triggered; honest
end-to-end record), the reconnect-hedge fix + both soak flakes, hydration
materialize (typewriter fix), the groom sweep, and the
epic-durable-transcript-ownership arc (durable v1 codec, timestamp
ownership, native events, re-derivation retirement — thorough-reviewed).
Component targets: app 0.8.0+16, pi-extension 0.3.0 (architectural),
relay 0.5.1 unchanged.

## Bound items

- epic-durable-transcript-ownership
- epic-durable-transcript-ownership-durable-event-log
- epic-durable-transcript-ownership-durable-event-log-backfill-reopen
- epic-durable-transcript-ownership-durable-event-log-codec-and-log
- epic-durable-transcript-ownership-durable-event-log-sdk-binding
- epic-durable-transcript-ownership-durable-native-events
- epic-durable-transcript-ownership-durable-native-events-compaction
- epic-durable-transcript-ownership-durable-native-events-steering
- epic-durable-transcript-ownership-durable-native-events-tool-events
- epic-durable-transcript-ownership-retire-rederivation
- epic-durable-transcript-ownership-retire-rederivation-two-source-boundary
- epic-perf-optimization-campaign
- feature-app-edge-trigger-room-snapshot-consumers
- feature-app-edge-trigger-room-snapshot-consumers-opt-1
- feature-app-edge-trigger-room-snapshot-consumers-opt-2
- feature-app-incremental-transcript-projection-pipeline
- feature-app-incremental-transcript-projection-pipeline-opt-1
- feature-app-incremental-transcript-projection-pipeline-opt-2
- feature-app-incremental-transcript-projection-pipeline-opt-3
- feature-canonical-transcript-timestamp-ownership
- release-v0.8.0
- story-app-debug-ring-constant-time-admission-and-coalesced-flush
- story-canonical-transcript-ordering-systematic-ts-provenance-sweep
- story-canonical-transcript-timestamp-ownership-app-consume-cleanup
- story-canonical-transcript-timestamp-ownership-error-frame-ts
- story-canonical-transcript-timestamp-ownership-extension-producer-ts
- story-canonical-transcript-timestamp-ownership-ownership-foundation
- story-fix-app-compound-recovery-no-peer
- story-fix-app-hydration-replay-should-materialize-not-stream
- story-fix-app-post-quiescence-working-stuck
- story-fix-app-reconnect-hedge-auth-boundary-and-post-adoption-cancel
- story-fix-app-ring-retention-under-flood

## Gate runs
(planned: security, tests, cruft, docs, patterns, refactor — then manual UAT)

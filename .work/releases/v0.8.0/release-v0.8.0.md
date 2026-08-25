---
id: release-v0.8.0
kind: release
stage: released
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

- **gate-tests** (2026-08-25) — 7 findings (High=6, Low=1; inline scanner, reduced isolation)

(planned: security, tests, cruft, docs, patterns, refactor — then manual UAT)
- **gate-security** (2026-08-25) — 1 findings (Critical=0, High=0, Medium=1, Low=0; inline audit with reduced isolation by operator instruction)
- **gate-cruft** (2026-08-25) — 6 findings (High=6; inline scan, reduced isolation because no scanner subagent was available)
- **gate-docs** (2026-08-25) — 12 findings (inline source-read-only audit; scanner tool unavailable): 1 changelog, 2 operational/readme surfaces, 9 pattern-skill anchors/contracts.
- **gate-refactor** (2026-08-25) — 10 findings (High=9, Medium=1) from 4 libraries: boundaries (0), documentation (6), lifecycle (2), protocol-contract (2); inline scanner, reduced isolation because no scanner subagent was available.
- **gate-patterns** (2026-08-25) — 4 patterns extracted; inline source-read-only audit, reduced isolation because the scanner subagent tool was unavailable.


## Shipped

- **Date**: 2026-08-25
- **Mapping**: tag-based (`v0.8.0`; force-push to publish the APK-stripped rewritten history; probe commits discarded per lease)
- **Items shipped**: 70 (69 active-bound moved here; 1 late-bound stub stays in archive per retain-bodies)
- **Gate totals**: 36 findings fixed in-release; 4 patterns codified; 2 live battery regressions found+fixed (durable session writer; pairing failure surface)
- **UAT**: operator ack 2026-08-25; battery all-green (soak/grid/state-shapes/mesh/capture-delivery); APK 0.8.0+16
- **Distribution**: FIRST GitHub-Release-distributed build (asset: app-debug.apk 0.8.0+16). `.work/artifacts/` retired.

## Shipped items

Bodies live on disk (retain-bodies) here and in `.work/archive/` for stubs.

| id | title | kind | archived_atop | git ref |
|----|-------|------|---------------|---------|
| epic-durable-transcript-ownership | Durable transcript ownership (the extension owns its transcript event log) | epic | — | b0310e69 |
| epic-perf-optimization-campaign | Performance and optimization campaign (v0.8.0 arc) | epic | — | b0310e69 |
| epic-durable-transcript-ownership-durable-event-log | F1 — Durable transcript event log (foundation) | feature | — | b0310e69 |
| epic-durable-transcript-ownership-durable-native-events | F3 — Durable-ize Outpost-Pi-specific transcript events | feature | — | b0310e69 |
| epic-durable-transcript-ownership-retire-rederivation | F4 — Retire SDK-message re-derivation + two-source contract | feature | — | b0310e69 |
| feature-app-edge-trigger-room-snapshot-consumers | Make room-snapshot consumers edge-triggered | feature | — | b0310e69 |
| feature-app-incremental-transcript-projection-pipeline | Incremental transcript append and projection pipeline | feature | — | b0310e69 |
| feature-canonical-transcript-timestamp-ownership | Canonical transcript timestamp ownership (close the single-clock invariant) | feature | — | b0310e69 |
| epic-durable-transcript-ownership-durable-event-log-backfill-reopen | Reconcile durable entries on compaction-aware reopen | story | — | b0310e69 |
| epic-durable-transcript-ownership-durable-event-log-codec-and-log | Define the durable transcript codec and log contract | story | — | b0310e69 |
| epic-durable-transcript-ownership-durable-event-log-sdk-binding | Bind durable transcript recording to the fresh SDK appendEntry capability | story | — | b0310e69 |
| epic-durable-transcript-ownership-durable-native-events-compaction | Persist compaction markers | story | — | b0310e69 |
| epic-durable-transcript-ownership-durable-native-events-steering | Persist steering events | story | — | b0310e69 |
| epic-durable-transcript-ownership-durable-native-events-tool-events | Persist native tool request/result events | story | — | b0310e69 |
| epic-durable-transcript-ownership-retire-rederivation-two-source-boundary | Bound transcript fallback to mixed-era reconciliation | story | — | b0310e69 |
| feature-app-edge-trigger-room-snapshot-consumers-opt-1 | Delete redundant room-snapshot transcript scans | story | — | b0310e69 |
| feature-app-edge-trigger-room-snapshot-consumers-opt-2 | Coalesce Chat/Home room-snapshot consumer work | story | — | b0310e69 |
| feature-app-incremental-transcript-projection-pipeline-opt-1 | Build the canonical incremental transcript reducer | story | — | b0310e69 |
| feature-app-incremental-transcript-projection-pipeline-opt-2 | Return accepted append receipts and batch Hive persistence | story | — | b0310e69 |
| feature-app-incremental-transcript-projection-pipeline-opt-3 | Wire append receipts to delta message materialization | story | — | b0310e69 |
| gate-cruft-extension-plaintext-envelope-comment | Remove the stale plaintext-envelope claim from extension integration tests | story | — | b0310e69 |
| gate-cruft-room-snapshot-benchmark-scaffolding | Remove superseded baseline scaffolding from the room-snapshot benchmark | story | — | b0310e69 |
| gate-cruft-sdk-transcript-message-tool-name | Remove the unused SDK transcript message tool-name field | story | — | b0310e69 |
| gate-cruft-transcript-turn-status-alias | Remove the obsolete transcript turn-status compatibility alias | story | — | b0310e69 |
| gate-cruft-unused-hot-reload-path-helpers | Remove unused hot-reload path helpers | story | — | b0310e69 |
| gate-cruft-ws-transport-post-rollback-comment | Remove the stale post-rollback plaintext claim from the app transport comment | story | — | b0310e69 |
| gate-docs-changelog-reconnect-hedge-cured | CHANGELOG keeps the cured reconnect-hedge issue under Unreleased known issues | story | — | b0310e69 |
| gate-docs-e2e-readme-empty-soak-inventory | E2E README describes a six-id known-open inventory and exit path that no longer  | story | — | b0310e69 |
| gate-docs-pattern-asymmetric-threshold-anchor-v080 | Asymmetric-threshold pattern points at post-probe connection code | story | — | b0310e69 |
| gate-docs-pattern-edge-triggered-anchors-v080 | Edge-triggered pattern anchors no longer identify the current room and turn emit | story | — | b0310e69 |
| gate-docs-pattern-failure-first-anchors-v080 | Failure-first pattern anchors drifted in the transcript and reconnect tests | story | — | b0310e69 |
| gate-docs-pattern-frame-byte-admission-anchor-v080 | Frame-byte pattern points at the wrong WebSocket queue lines | story | — | b0310e69 |
| gate-docs-pattern-generation-fenced-sync-anchor-v080 | Generation-fenced pattern points at the pre-reducer sync activation range | story | — | b0310e69 |
| gate-docs-pattern-owner-channel-loss-anchor-v080 | Owner-channel resource pattern points at pre-hedge connection-loss code | story | — | b0310e69 |
| gate-docs-pattern-single-source-durable-fallback | Single-source identity pattern retains the deleted transcript recorder and old f | story | — | b0310e69 |
| gate-docs-pattern-snapshot-reconciliation-api | Snapshot-replay pattern documents the deleted SDK transcript mapper | story | — | b0310e69 |
| gate-docs-pattern-stale-capability-anchors-v080 | Stale-capability pattern anchors drifted after durable transcript binding | story | — | b0310e69 |
| gate-docs-triage-archived-blank-chat-id | Debug-capture triage still emits the archived blank-chat work item as live | story | — | b0310e69 |
| gate-patterns-v0.8.0 | Patterns extracted for v0.8.0 | story | — | b0310e69 |
| gate-refactor-documentation-durable-encoder-throws | Document the durable transcript encoder failure contract | story | — | b0310e69 |
| gate-refactor-documentation-sdk-transcript-contracts | Document the SDK projection's durable transcript API | story | — | b0310e69 |
| gate-refactor-documentation-session-history-throws | Document session-history replay precondition failures | story | — | b0310e69 |
| gate-refactor-documentation-transcript-log-contracts | Document TranscriptEventLog public service contracts | story | — | b0310e69 |
| gate-refactor-documentation-transcript-store-errors | Document transcript store validation and read failures | story | — | b0310e69 |
| gate-refactor-documentation-ws-connect-errors | Document WebSocket connect failure and cancellation outcomes | story | — | b0310e69 |
| gate-refactor-lifecycle-debug-flush-dispose | Give the debug flush drain an awaited teardown boundary | story | — | b0310e69 |
| gate-refactor-lifecycle-hedge-cancel-teardown | Make hedge cancellation teardown total under cleanup failures | story | — | b0310e69 |
| gate-refactor-protocol-contract-history-type-literals | Derive transcript history discriminators from generated protocol facts | story | — | b0310e69 |
| gate-refactor-protocol-contract-transcript-v1-island | Give the durable transcript v1 format a schema-owned or documented home | story | — | b0310e69 |
| gate-security-pairing-auth-stall-socket-leak | Pairing cannot cancel a socket stalled at post-auth readiness | story | — | b0310e69 |
| gate-tests-durable-reopen-topology-interleavings | Exercise durable transcript reopen across deep forks, compaction, and producer i | story | — | b0310e69 |
| gate-tests-hedge-real-socket-cancellation | Prove reconnect hedge loser cancellation at the real WebSocket boundary | story | — | b0310e69 |
| gate-tests-hydration-live-boundary-matrix | Exercise hydration coalescing at every live-turn boundary | story | — | b0310e69 |
| gate-tests-perf-regressions-fail-default-suite | Make the v0.8.0 performance contracts fail a routine verification lane | story | — | b0310e69 |
| gate-tests-projection-adversarial-equivalence | Pin incremental projection equivalence under adversarial event histories | story | — | b0310e69 |
| gate-tests-prune-perf-f2-f3-duplicates | Remove obsolete benchmark baselines and duplicated F2/F3 producer coverage | story | — | b0310e69 |
| gate-tests-soak-terminal-boundary-behavior | Replace the soak terminal-boundary source check with behavioral evidence | story | — | b0310e69 |
| story-app-debug-ring-constant-time-admission-and-coalesced-flush | Make debug-ring admission constant-time and coalesce snapshot flushes | story | — | b0310e69 |
| story-canonical-transcript-ordering-systematic-ts-provenance-sweep | Systematic ts-provenance sweep (close the single-clock invariant) | story | — | b0310e69 |
| story-canonical-transcript-timestamp-ownership-app-consume-cleanup | App consume + fallback cleanup (close the app-side residuals) | story | — | b0310e69 |
| story-canonical-transcript-timestamp-ownership-error-frame-ts | Error-frame ts (schema + extension + app + codegen) | story | — | b0310e69 |
| story-canonical-transcript-timestamp-ownership-extension-producer-ts | Extension producer-ts coverage (agent_done, user_message echoes, mesh cards) | story | — | b0310e69 |
| story-canonical-transcript-timestamp-ownership-ownership-foundation | Timestamp-ownership foundation (extension owns the canonical ts) | story | — | b0310e69 |
| story-fix-app-compound-recovery-no-peer | Compound network recovery no longer strands the live-device soak in no-peer | story | — | b0310e69 |
| story-fix-app-hydration-replay-should-materialize-not-stream | Hydration replays completed turns through the streaming UI (typewriter backfill) | story | — | b0310e69 |
| story-fix-app-post-quiescence-working-stuck | Live soak recovery probes now terminate before post-soak quiescence | story | — | b0310e69 |
| story-fix-app-reconnect-hedge-auth-boundary-and-post-adoption-cancel | Reconnect hedge misses the auth-read stall and mis-cancels after adoption (super | story | — | b0310e69 |
| story-fix-app-ring-retention-under-flood | Preserve newest debug-ring rows during flood export | story | — | b0310e69 |
| story-fix-ext-durable-session-live-regression | Preserve durable transcript writes after live session replacement | story | — | b0310e69 |
| story-fix-pairing-failure-surface-bounded | Surface pairing timeout failure without waiting for transport teardown | story | — | b0310e69 |

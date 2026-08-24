---
id: feature-app-edge-trigger-room-snapshot-consumers
kind: feature
stage: drafting
tags: [perf, app]
parent: epic-perf-optimization-campaign
depends_on: []
release_binding: null
gate_origin: perf-design
created: 2026-08-24
updated: 2026-08-24
---

# Make room-snapshot consumers edge-triggered

## Brief

Bottleneck: the `roomsStream` listeners in
`app/lib/data/sync/sync_service.dart` and
`app/lib/ui/chat/viewmodels/chat_viewmodel.dart`. Every canonical room snapshot
schedules runtime/session work; a live bound session reaches
`SyncService._resendHeldPendingMessages`, which performs a full transcript-event
read and scan even when there are no held messages, while `ChatViewModel`
serializes a binding refresh and recomputes immediately and again after that
async path. The partial 159-second device soak observed **10 room snapshots**;
the motivating 11-hour capture had **339**. At the 5,500-event stress size, the
actual encrypted Hive `readSession` called by the resend sweep cost **20.755 ms
p50 / 34.014 ms p95**, so 339 metadata snapshots can imply about **7.0 seconds
of full-log read time** before ViewModel rebuild work. Proposed hierarchy level:
**Algorithmic / data model** and **I/O / service boundary**, with **workload,
storage-I/O, and UI fan-out** probes.

## Optimization direction for the design pass

Classify room emissions at the boundary into the semantic edges consumers need:
transport-generation/liveness transition, session-id rotation, relevant active-
room metadata change, and no relevant change. Session rebind and held-send
replay should run only for their owning edge; presentation should recompute once
per semantic change. Preserve full canonical snapshots as the source of truth —
do not add a second stale cache or debounce away convergence.

The transcript anchoring callback is not the diagnosed source: `_MessageList`
only schedules it when message identities or streaming content change. The
design should prevent room-only notifications from causing unnecessary chat
rebuilds rather than weakening anchor restoration.

## Simplification opportunity

Delete the unconditional room-snapshot transcript scan, duplicate
`ChatViewModel._recompute` path, and rebind work for unchanged session identity.
Prefer one derived edge/event over additional sticky booleans.

## Discovery constraints for perf-design

- Benchmark 339 snapshots against empty, 200-event, and 5,500-event sessions;
  count Hive reads, binding refreshes, `notifyListeners`, widget rebuilds, and
  post-frame anchor callbacks.
- Preserve reconnect hydration, session rotation, held-pending resend, stale
  room gating, multi-client updates, and `working:false` convergence.
- Use explicit stream barriers/fake clocks rather than elapsed-time sleeps for
  lifecycle correctness tests.

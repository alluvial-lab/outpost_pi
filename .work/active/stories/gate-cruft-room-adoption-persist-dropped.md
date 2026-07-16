---
kind: story
release_binding: null
parent: feature-app-async-lifecycle-ownership
stage: drafting
id: gate-cruft-room-adoption-persist-dropped
tags: [cleanup]
depends_on: []
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-01
---

# Legacy room-adoption persistence failures are dropped

## Severity
Medium

## Location
app/lib/data/transport/connection_manager.dart:1117

## Issue
_storage.savePeer(updated).catchError((...) {}) ignores failures when persisting migrated room IDs; this can leave room migration state inconsistent across reconnect/restart without trace.

## Recommendation
Keep fail-fast logging/telemetry and a retry path (or dead-letter queue) for migration persistence, while preserving non-fatal behavior.

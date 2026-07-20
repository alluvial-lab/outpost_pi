---
id: feature-secure-transcript-storage-migrate-legacy-transcripts
kind: story
stage: done
tags: [app, security]
parent: feature-secure-transcript-storage
depends_on: [gate-security-transcript-box-name-collision, gate-security-transcript-boxes-unencrypted]
release_binding: app-v0.2.0
gate_origin: security
created: 2026-07-18
updated: 2026-07-20
---

# Migrate legacy plaintext transcripts without loss or double writes

## Checkpoint

Perform a blocking, versioned migration during `LocalBoxes.init()` after the
secure Hive key and v3 destination names exist but before dependency setup or
`runApp`. The migration is the only legacy reader; normal services open only
the encrypted v3 boxes.

Use canonical `sessions_index` rows to group old lossy box names. Partition
legacy event records by their embedded `session_id`; import a unique
projection-only session into deterministic synthetic transcript events so
pre-event-log history remains rebuildable. Never guess when a collided source
cannot be attributed.

## Ordering

Depends on:

- `gate-security-transcript-box-name-collision` — v3 destination identities
- `gate-security-transcript-boxes-unencrypted` — secure key and cipher-backed destinations

The feature worker should implement this checkpoint in the same cohesive app
persistence bundle after both destination contracts are established.

## Acceptance evidence

- A plaintext indexed session migrates to encrypted event/index storage and is
  visible through existing repositories after restart.
- A lossy-name collision with distinct embedded session IDs is partitioned
  without cross-session rows.
- A unique projection-only legacy session is converted to deterministic events
  and retains visible message order/content after projection rebuild.
- Ambiguous, malformed, or conflicting source data throws a stable migration
  error and leaves the legacy source untouched.
- A crash after partial destination writes resumes idempotently without event
  duplication or any live old/new double-write path.
- Source deletion occurs only after full destination re-read/validation, and
  the migration completion marker is written last.

## Implementation notes
- Execution capability: `openai-codex/gpt-5.6-sol` (caller-selected for destructive, security-critical Hive migration work).
- Review weight: `standard` (caller override); child checkpoint advances directly to done and is reviewed only at the parent feature boundary.
- Files changed: `app/lib/data/local/boxes.dart`, `app/lib/data/local/legacy_projection_import.dart`, `app/lib/data/local/transcript_storage_migration.dart`, `app/test/data/local/transcript_storage_migration_test.dart`.
- Tests added: file-backed Hive coverage for encrypted event/index migration and restart readback, lossy-name collision partitioning, deterministic projection-only import, malformed/ambiguous/conflicting fail-closed behavior, partial-copy resume, partial-deletion resume, source retention, and completion-marker ordering.
- Simplification: legacy naming and plaintext reads exist only inside the boot migrator; normal access remains v3-only, and the existing SyncService activation projection rebuild consumes migrated event logs without a new compatibility hook or double-write path.
- Discrepancies from design: added a content-free `migration_copy_verified_v3` phase marker before deletion. Hive cannot atomically delete several boxes, so this marker lets a crash after one verified source deletion resume cleanup without needing the deleted source; it is removed before `migration_version = 3`, which remains the last completion write. No `sync_service.dart` edit was needed because activation already calls `_materializeTranscriptProjectionForRef`.
- Adjacent issues parked: none.

## Verification
- Targeted analyzer: `dart analyze lib/data/local/boxes.dart lib/data/local/legacy_projection_import.dart lib/data/local/transcript_storage_migration.dart test/data/local/transcript_storage_migration_test.dart` — no issues.
- Migration/storage suite: `flutter test --no-pub test/data/local/transcript_storage_migration_test.dart test/data/local/transcript_storage_key_test.dart test/data/local/transcript_event_store_hive_test.dart test/data/local/records_test.dart test/data/local/transcript_box_identity_test.dart` — 32 passed.
- Authoritative full suite: `flutter test --no-pub` — 762 passed, 3 unrelated failures. One is the pre-existing `sync_service_test.dart` compaction-convergence baseline; two arose from concurrent uncommitted debug/e2e work outside this story (`debug_capture_routing_test.dart` load failure and `qr_lifecycle_e2e_test.dart`). No migration/storage test failed.
- Full `flutter analyze --no-pub` was not green because concurrent/unrelated package example and debug-capture edits produced errors; the touched-file analyzer above is green.
- Device smoke was not run. The destructive state machine is verified against temporary real file-backed Hive databases, including AES destinations, close/reopen restarts, injected crashes in copy and deletion phases, exact destination re-read, and on-disk source deletion; production differs only in `Hive.initFlutter` path selection and the separately tested secure-key adapter, so no device-only safety blocker remains.

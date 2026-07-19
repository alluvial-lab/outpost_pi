---
id: feature-secure-transcript-storage-migrate-legacy-transcripts
kind: story
stage: implementing
tags: [app, security]
parent: feature-secure-transcript-storage
depends_on: [gate-security-transcript-box-name-collision, gate-security-transcript-boxes-unencrypted]
release_binding: null
gate_origin: security
created: 2026-07-18
updated: 2026-07-18
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

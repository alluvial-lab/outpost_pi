---
id: gate-security-unindexed-plaintext-transcripts-retained
kind: story
stage: done
tags: [app, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-20
updated: 2026-07-28
---

# Migration can complete while unindexed plaintext transcript boxes remain

## Severity
Medium

## Domain
Data Protection

## Relevance
Release-relevant

## Location
`app/lib/data/local/boxes.dart:93`

## Evidence
```dart
if (!await Hive.boxExists(TranscriptStorageMigrator.legacyIndexBoxName)) {
  await metadata.delete(TranscriptStorageMigrator.copyVerifiedKey);
  await metadata.put(
    TranscriptStorageMigrator.migrationVersionKey,
    TranscriptStorageMigrator.migrationVersion,
```

The migration marks v3 complete as soon as `sessions_index` is absent. When it is present, cleanup still derives source names only from index candidates (`app/lib/data/local/transcript_storage_migration.dart:560`). A legacy `msgs_*` or `transcript_events_*` file omitted from or outliving that manifest is therefore never encrypted, quarantined, or deleted, and the completion marker prevents future migration attempts. Such plaintext remnants can persist in the app sandbox and device backups despite the release's encrypted transcript storage boundary.

## Remediation direction
Before writing the completion marker, inventory the app-owned Hive directory for legacy transcript filename generations and apply an explicit policy to every match. Preserve data integrity by quarantining unknown sources or requiring an operator-confirmed discard rather than guessing attribution, but do not silently declare migration complete while plaintext transcript files remain. Add coverage for an orphan legacy box with both missing and incomplete legacy indexes.

## Audit execution
The release scanner ran inline in the gate orchestrator context as explicitly requested, without a nested scanner; independent-context isolation was therefore reduced.

## Implementation notes

- `LocalBoxes` now inventories legacy `msgs_*` and `transcript_events_*` Hive files before migration completion.
- Missing indexes and index manifests that omit an on-disk source fail closed with `unindexed_legacy_source`; unknown plaintext data is retained rather than discarded.
- Added missing-index and incomplete-index orphan coverage in `transcript_storage_migration_test.dart`.
- Verification: `flutter test test/data/local/transcript_storage_migration_test.dart --concurrency=2` (14 passing).

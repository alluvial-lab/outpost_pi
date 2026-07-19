---
id: feature-secure-transcript-storage
kind: feature
stage: review
tags: [app, security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-15
updated: 2026-07-18
---

# App: secure and collision-safe durable transcript storage

## Brief

Two security gate findings describe the durable transcript Hive boxes on the
mobile app: distinct room/session identifiers can map to the same box name
(collision), and the boxes are opened as default (unencrypted) Hive boxes.
Together: messages from one session can be misattributed to another, and the
transcript is persisted in plaintext. This feature makes transcript storage
collision-safe and encrypted:

- `gate-security-transcript-box-name-collision` — distinct room/session identifiers map to the same transcript box name after sanitization
- `gate-security-transcript-boxes-unencrypted` — transcript event logs opened as default Hive boxes without an encryption cipher

## Simplification opportunity

Derive box names from a collision-free key (or namespace by room+session);
enable a Hive encryption cipher for transcript boxes. Behavior change: existing
unencrypted boxes are migrated or superseded on first launch after upgrade.

## Source

Promoted from backlog by `scope` (2026-07-15). 2
`gate-security-transcript-box-*` findings from the v0.6.0 release
`gate-security` pass.

## Design decisions

- **Encrypted scope**: Encrypt the canonical `transcript_events` logs, the disposable `msgs` projections, and `sessions_index` — all three persist transcript content or previews. `runtime` remains plaintext because it contains only volatile reachability and is wiped at boot.
- **Box identity**: Use a versioned, lowercase full SHA-256 digest of an injective JSON tuple `[peerId, roomId, sessionId]`, with separate `transcript_events_v3_` and `msgs_v3_` prefixes. A reversible encoding can exceed Hive's 255-character ASCII box-name limit; full SHA-256 is bounded, case-folding safe, and collision-resistant. Add `crypto` as a direct dependency rather than relying on its transitive presence.
- **Key ownership**: Generate one 32-byte Hive key with `Hive.generateSecureKey()`, encode it for `FlutterSecureStorage`, and reuse it for all encrypted transcript boxes. A plaintext, content-free security metadata box records that a key has been provisioned. If that marker exists but the secure key is missing, malformed, or the encrypted box rejects it, fail closed; never generate a replacement over unreadable data.
- **Migration boundary**: Block bootstrap in `LocalBoxes.init()` until a versioned, idempotent migration completes. Legacy boxes are read-only during the copy; normal services start only after new encrypted boxes validate, so there is no double-write window.
- **Existing transcript preservation**: Copy canonical event logs first. Legacy lossy-name collisions are grouped from canonical `sessions_index` rows and event records are partitioned by their embedded `session_id`. A unique legacy `msgs` projection with no event log is converted into deterministic synthetic transcript events so pre-event-log installs retain offline history. If attribution remains ambiguous or a record cannot be validated, abort migration and retain the plaintext source rather than delete or misattribute it.
- **Legacy cleanup**: Delete a legacy source only after every destination value has been re-read and compared. Partial destinations are safe to resume. Mark migration complete only after all known indexed sources succeed; abandoned boxes not represented in the canonical index are not guessed at or silently deleted.
- **UI surface**: None. Migration occurs before `runApp`; the existing app reads the same repositories after bootstrap. Exceptional key loss or irreducibly ambiguous legacy data is a fail-closed startup error, not a new recovery screen in this feature.
- **Dispatch/review**: Direct-read mapping was sufficient for this bounded app persistence surface. The effective implementation review weight is `standard` (caller default). Design-time fresh-context advisory was not dispatched because this delegated worker has no nested subagent adapter; this is non-blocking under the advisory policy.

## Architectural choice

### Option A — New encrypted generation plus staged migration (chosen)

Introduce v3 collision-resistant box names and encrypted common/per-session
boxes, then migrate legacy plaintext data before app services start. This
optimizes for data integrity, resumability, and an auditable hard cutover at the
cost of a dedicated migration coordinator and focused boot tests.

### Option B — Reopen current boxes with a cipher

Keep current names and add `encryptionCipher` to `Hive.openBox`. This is small,
but Hive cannot reinterpret an existing plaintext file as encrypted, and the
lossy `_safe` identity still aliases distinct sessions. It does not meet either
finding.

### Option C — Abandon the old namespace and re-sync

Start empty encrypted boxes and let Pi history refill them. This is simplest,
but it loses offline-only, pending, or otherwise unreplayable transcript data
and silently strands plaintext files. It violates the explicit preservation
constraint.

Option A is the least irreversible sound choice: old data remains untouched
until the encrypted copy proves complete, while all post-bootstrap writes use
only the new generation.

## Trickiest unit first

The migration coordinator is the riskiest unit because Hive has no cross-box
transaction and the old lossy names may already represent more than one
canonical identity. Its design therefore makes migration a boot-time,
idempotent copy/verify/delete state machine; it never infers attribution from a
lossy filename alone.

## Implementation Units

### Unit 1: Collision-resistant transcript box identity

**Files**:
- `app/lib/data/local/transcript_box_identity.dart`
- `app/lib/data/local/boxes.dart`
- `app/pubspec.yaml`
- `app/pubspec.lock`
- `app/test/data/local/transcript_box_identity_test.dart`

**Story**: `gate-security-transcript-box-name-collision` (existing checkpoint)

```dart
final class TranscriptBoxIdentity {
  const TranscriptBoxIdentity._();

  static String digest({
    required String peerId,
    required String roomId,
    required String sessionId,
  });

  static String eventsName(TranscriptSessionKey key);
  static String messagesName(RemoteSessionRef ref);
}
```

**Implementation Notes**:
- Hash the UTF-8 encoding of `jsonEncode(<String>[peerId, roomId, sessionId])`; JSON array encoding preserves segment boundaries, unlike delimiter concatenation.
- Emit only lowercase hexadecimal and fixed prefixes, keeping names ASCII, below Hive's 255-character assertion, and stable under Hive's lowercase normalization.
- Replace both public name helpers with this single identity helper. Keep the old `_safe` derivation private to migration only, then remove `_safe` from normal box access.
- Declare the already-locked `crypto` package directly because production code imports it.

**Acceptance Criteria**:
- [ ] Inputs that collide under `_safe` (including unsafe-character replacement and underscore-run collapse) produce distinct event and message box names.
- [ ] The same canonical tuple is deterministic across calls; changing any one segment changes the result.
- [ ] Every generated name is lowercase ASCII and no longer than 255 characters, even for long Unicode identifiers.
- [ ] No normal accessor can open a legacy lossy-name box.

---

### Unit 2: Secure Hive key lifecycle and encrypted box facade

**Files**:
- `app/lib/data/local/transcript_storage_key.dart`
- `app/lib/data/local/boxes.dart`
- `app/lib/main.dart`
- `app/test/data/local/transcript_storage_key_test.dart`
- `app/test/data/local/records_test.dart`
- `app/test/data/local/transcript_event_store_hive_test.dart`

**Story**: `gate-security-transcript-boxes-unencrypted` (existing checkpoint)

```dart
abstract interface class TranscriptKeyValueStore {
  Future<String?> read();
  Future<void> write(String encodedKey);
}

final class SecureTranscriptKeyValueStore implements TranscriptKeyValueStore {
  SecureTranscriptKeyValueStore([FlutterSecureStorage? storage]);

  @override
  Future<String?> read();

  @override
  Future<void> write(String encodedKey);
}

final class TranscriptStorageKeyManager {
  TranscriptStorageKeyManager(this._store);

  Future<Uint8List> loadOrCreate({required bool keyWasProvisioned});
}

final class TranscriptStorageKeyException implements Exception {
  const TranscriptStorageKeyException(this.code);
  final String code;
}

class LocalBoxes {
  static Future<void> init({TranscriptKeyValueStore? keyStore});

  static Future<void> initForTest(
    String path, {
    List<int>? encryptionKey,
  });
}
```

**Implementation Notes**:
- Production defaults to `SecureTranscriptKeyValueStore`; tests inject fixed 32-byte keys and never invoke a platform channel.
- Write, re-read, base64-decode, and length-check the first generated key before marking it provisioned. Share a single in-flight initialization future so concurrent callers cannot race key generation.
- Open `sessions_index_v3`, `transcript_events_v3_*`, and `msgs_v3_*` with one `HiveAesCipher`. Pass the cipher on every first open; Hive ignores open parameters for an already-open box.
- Keep `transcript_security_meta` content-free and plaintext so key-loss can be distinguished from a first upgrade with legacy plaintext data.
- Convert wrong-key, malformed-key, and key-missing-after-provisioning failures into stable `TranscriptStorageKeyException` codes without logging key bytes or transcript values.

**Acceptance Criteria**:
- [ ] First boot creates exactly one 32-byte key and subsequent boots reuse it.
- [ ] Concurrent first access cannot generate different keys.
- [ ] A provisioned installation with a missing/malformed key fails before opening or writing transcript boxes.
- [ ] Event logs, message projections, and session previews are opened with `HiveAesCipher`; runtime remains volatile and unencrypted.
- [ ] A file-level regression writes a unique transcript sentinel and confirms the new Hive files do not contain its UTF-8 plaintext bytes.

---

### Unit 3: Idempotent legacy migration and projection import

**Files**:
- `app/lib/data/local/transcript_storage_migration.dart`
- `app/lib/data/local/legacy_projection_import.dart`
- `app/lib/data/local/boxes.dart`
- `app/lib/data/sync/sync_service.dart`
- `app/test/data/local/transcript_storage_migration_test.dart`
- `app/test/data/sync/sync_service_test.dart`

**Story**: `feature-secure-transcript-storage-migrate-legacy-transcripts`

```dart
final class TranscriptMigrationReport {
  const TranscriptMigrationReport({
    required this.sessions,
    required this.events,
    required this.importedProjectionRows,
    required this.deletedLegacyBoxes,
  });

  final int sessions;
  final int events;
  final int importedProjectionRows;
  final int deletedLegacyBoxes;
}

final class TranscriptMigrationException implements Exception {
  const TranscriptMigrationException({
    required this.code,
    required this.sourceBox,
  });

  final String code;
  final String sourceBox;
}

final class LegacyProjectionImport {
  const LegacyProjectionImport._();

  static List<TranscriptEvent> toEvents({
    required TranscriptSessionKey session,
    required Iterable<MessageRecord> rows,
  });
}

final class TranscriptStorageMigrator {
  TranscriptStorageMigrator({required HiveCipher cipher});

  Future<TranscriptMigrationReport> migrate({
    required Box<dynamic> legacyIndex,
    required Box<dynamic> secureIndex,
  });
}
```

**Implementation Notes**:
- Run after Hive path initialization and key validation, but before `_initialized`, dependency registration, `SyncService`, or `runApp`.
- Parse canonical `SessionIndexRecord`s from the old index and group them by the exact old event/message box names. Open old sources without a cipher and new destinations with the v3 cipher.
- Route each `TranscriptEventRecord` only when its embedded `session_id` selects exactly one candidate. Validate destination conflicts by key and full serialized value; an unequal existing value is an error, not an overwrite.
- For a unique candidate whose event log is absent/empty but legacy `msgs` has rows, convert `MessageRecord`s to deterministic synthetic events in sequence order. Preserve timestamps, text/images, tool request/result state, compaction data, and pending/confirmed user state. IDs must be deterministic so a retry deduplicates.
- For a collided projection, canonical event records win and `SyncService._materializeTranscriptProjectionForRef` rebuilds the new encrypted `msgs` box on activation. If the shared projection contains the only copy for any candidate, throw `ambiguous_legacy_projection` and retain all sources.
- Copy the session index only after its referenced transcript sources validate. Re-read every destination value before adding the source to the deletion phase. Deletion happens after the complete copy/verify phase; a crash at any point resumes by comparing existing destinations.
- Set `migration_version = 3` only after deletion completes. Normal accessors never write old names, so migration and live writes cannot overlap.
- Do not enumerate or delete unindexed legacy files by guessed filesystem conventions. They remain abandoned and untouched; indexed history is the supported migration boundary.

**Acceptance Criteria**:
- [ ] A unique plaintext legacy session (events and/or projection-only) reappears through the normal encrypted repositories with the same visible order/content.
- [ ] Two old identities that share one lossy name are separated by embedded event `session_id` without cross-session rows.
- [ ] Irreducibly ambiguous, malformed, or conflicting data aborts before the source is deleted and before normal app services start.
- [ ] An injected crash after partial destination writes is idempotently resumed without duplicate events or a second live write path.
- [ ] Legacy source boxes and plaintext index are deleted only after destination verification; the completion marker is last.
- [ ] Activation rebuilds a collided/discarded `msgs` projection from its migrated canonical event log.

## Implementation Order

1. `gate-security-transcript-box-name-collision` — land v3 identity derivation and regression tests.
2. `gate-security-transcript-boxes-unencrypted` — land secure key lifecycle and make all transcript-bearing destinations encrypted.
3. `feature-secure-transcript-storage-migrate-legacy-transcripts` — wire the boot migration, legacy projection import, cleanup, and restart/failure tests. It depends on both destination contracts above.
4. Run focused local tests during implementation, then `flutter analyze` and `flutter test` once for feature verification; no build or full suite belongs in this design pass.

## Simplification

- Remove lossy `_safe` from all live transcript box naming; retain one private legacy-name function only inside the migration adapter.
- Centralize the cipher and box identity in `LocalBoxes`; callers and repositories keep using the existing facade and cannot accidentally open plaintext transcript storage.
- Do not double-write old and new boxes or retain a permanent compatibility read path. Migration is the sole legacy reader and is retired at the completion marker.
- Reuse the existing canonical event projection rebuild rather than maintaining a second ongoing projection migration path.
- No foundation assertion changes: the app remains Hive-backed local cache with the same domain/repository boundaries; this feature hardens its storage adapter.

## Testing

- **Identity regression**: protect against the demonstrated `_safe` alias and Hive lowercase normalization, including long/Unicode identifiers.
- **Key lifecycle unit tests**: protect first-write atomicity, single-flight generation, malformed key handling, and fail-closed key loss with an in-memory `TranscriptKeyValueStore`.
- **Migration interface tests**: protect copy/verify/delete ordering, collision partitioning, projection-only imports, conflict refusal, and crash-resume idempotency against temporary real Hive directories.
- **Store integration test**: write/read through `HiveTranscriptEventStore` after a restart with the same key and assert the on-disk bytes do not contain a known plaintext sentinel.
- **Sync regression**: protect activation-time rebuilding of encrypted `msgs` from the migrated event log.
- Keep existing event-store ordering/dedupe tests; update their bootstrap helper to inject a fixed test key. No test is removed merely to accommodate encryption.

## Implementation
- Landed collision-resistant SHA-256 v3 box identities, one platform-secured AES key for every transcript-bearing box, and a blocking legacy migration before dependency setup and `runApp`.
- The migration treats the canonical plaintext index as its manifest, partitions collided event logs only by an unambiguous embedded `session_id`, converts unique projection-only history into deterministic canonical events, and rejects malformed, ambiguous, or conflicting data without deleting sources.
- Copy/verify/delete/mark is restart-safe across both partial destination writes and partial multi-box deletion. A temporary content-free copy-verified phase marker is removed before the final `migration_version = 3` completion write; normal services never open or write legacy names.
- Existing SyncService activation already rebuilds disposable encrypted `msgs` projections from migrated event logs, so no compatibility reader, double-write path, or concurrent `sync_service.dart` edit was required.
- Integrated verification: the focused migration/storage command passed 32 tests, the migration file-backed Hive suite passed all 8 idempotency/collision/projection/fail-closed/crash-resume tests, and analyzer coverage over every touched Dart file reported no issues.
- Authoritative `flutter test --no-pub` completed with 762 passing tests and 3 unrelated failures: the pre-existing SyncService compaction-convergence baseline plus concurrent uncommitted debug-capture and QR-e2e work outside this feature. No storage/migration test failed. Full-repo analyze was likewise obstructed by unrelated package-example/debug-capture errors; touched-file analysis is green.
- Device smoke was not run. The data-loss-sensitive paths use real temporary file-backed Hive databases with AES, close/reopen restarts, exact destination re-read, injected copy/deletion crashes, and source-file deletion; the platform-specific secure-key lifecycle was verified by the preceding checkpoint, leaving no device-only migration blocker.

## Risks

- **Riskiest assumption — index completeness**: Migration can safely identify only sessions represented by canonical `sessions_index` rows because Hive exposes existence/deletion by known name, not a portable box catalogue. Unindexed files are retained untouched rather than guessed or deleted; all indexed/user-visible history is migrated.
- **Already-collided legacy data**: Embedded event `session_id` usually resolves it, but equal session IDs across colliding peer/room identities cannot be attributed. The fallback is fail-closed preservation, not duplication or contamination.
- **Key loss/backup restore**: Hive data may outlive the platform secure-storage entry. The metadata marker prevents silent key rotation; recovery UX is outside this no-UI feature, so startup fails with a stable error while ciphertext remains untouched.
- **Non-transactional multi-box migration**: Copy/compare/delete phases and deterministic imported IDs make every operation repeatable. The completion marker is never written early.
- **Hive cipher limits**: This is local at-rest protection through Hive's supported `HiveAesCipher`, not protocol E2E encryption and not protection from a compromised, unlocked process. Product trust claims remain unchanged.

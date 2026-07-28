// Local transcript storage facade (Hive v3).
//
// Durable transcript-bearing data is encrypted with one platform-secured key:
//   sessions_index_v3                         -> SessionIndexRecord
//   transcript_events_v3_<sha256 tuple>       -> TranscriptEventRecord
//   msgs_v3_<sha256 tuple>                    -> MessageRecord projection
// Runtime reachability remains plaintext and is wiped on every boot.

import 'dart:async';
import 'dart:io';

import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/local/transcript_box_identity.dart';
import 'package:app/data/local/transcript_storage_key.dart';
import 'package:app/data/local/transcript_storage_migration.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

const String _kNamespace = 'rp_v2';
const String _kSessionsIndex = 'sessions_index_v3';
const String _kRuntime = 'runtime';
const String _kSecurityMeta = TranscriptStorageMigrator.metadataBoxName;
const String _kKeyProvisioned = 'key_provisioned_v3';
const String _kKeyVerifier = 'key_verifier_v3';
const String _kOwnerTransitionWipePending = 'owner_transition_wipe_pending';
const String _kTranscriptDiscardPending = 'transcript_discard_pending_v3';

/// Facade over encrypted transcript storage and volatile runtime state.
///
/// Production initialization provisions one platform-secured key before any
/// transcript-bearing box opens. Tests inject a fixed key and never call a
/// platform channel.
class LocalBoxes {
  static bool _initialized = false;
  static Future<void>? _initialization;
  static HiveCipher? _cipher;
  static bool _transitionGateClosed = false;
  static int _inFlightOpens = 0;
  static Completer<void>? _opensDrained;
  static Future<void>? _wipeInFlight;
  static Future<void>? _transcriptDiscardInFlight;

  /// Inject a test-only failure after latching but before common-box clearing.
  @visibleForTesting
  static Future<void> Function()? beforeOwnerTransitionCommonClearForTesting;

  /// Observe a test-only per-session deletion checkpoint.
  @visibleForTesting
  static Future<void> Function(String boxName)?
  afterOwnerTransitionBoxDeleteForTesting;

  /// Pause a test-only transcript open before Hive receives it.
  @visibleForTesting
  static Future<void> Function(String boxName)?
  beforeTranscriptBoxOpenForTesting;

  /// Observe a test-only per-box recovery deletion checkpoint.
  @visibleForTesting
  static Future<void> Function(String boxName)?
  afterTranscriptRecoveryBoxDeleteForTesting;

  /// Open transcript storage and converge any latched Owner-transition wipe.
  static Future<void> init({TranscriptKeyValueStore? keyStore}) {
    if (_initialized) return _convergePendingOwnerTransitionWipe();
    final inflight = _initialization;
    if (inflight != null) return inflight;
    late final Future<void> future;
    future = _initProduction(keyStore).whenComplete(() {
      if (identical(_initialization, future)) _initialization = null;
    });
    _initialization = future;
    return future;
  }

  /// Resume a latched Owner-transition wipe before a router boot retry.
  ///
  /// App startup initializes storage before routing; the uninitialized no-op
  /// keeps isolated router tests and pre-storage error paths side-effect free.
  static Future<void> convergePendingOwnerTransitionWipe() {
    if (!_initialized) return Future.value();
    return _convergePendingOwnerTransitionWipe();
  }

  static Future<void> _initProduction(TranscriptKeyValueStore? keyStore) async {
    await Hive.initFlutter(_kNamespace);
    final meta = await Hive.openBox<dynamic>(_kSecurityMeta);
    final effectiveKeyStore = keyStore ?? SecureTranscriptKeyValueStore();
    await _convergePendingTranscriptDiscard(meta, effectiveKeyStore);
    final key = await TranscriptStorageKeyManager(
      effectiveKeyStore,
    ).loadOrCreate(keyWasProvisioned: meta.get(_kKeyProvisioned) == true);
    await _validateKey(meta, key);
    _cipher = HiveAesCipher(key);
    await _openCommonOrConvergeWipe(meta);
    await _migrateLegacy(meta);
    await meta.put(_kKeyProvisioned, true);
    _initialized = true;
  }

  /// Open a test directory with an injected key and no platform-channel access.
  ///
  /// The deterministic default is test-only. Repeating this call simulates a
  /// restart and wipes the volatile box while preserving durable ciphertext.
  static Future<void> initForTest(
    String path, {
    List<int>? encryptionKey,
    TranscriptKeyValueStore? keyStore,
  }) async {
    Hive.init(path);
    final meta = await Hive.openBox<dynamic>(_kSecurityMeta);
    if (keyStore != null) {
      await _convergePendingTranscriptDiscard(meta, keyStore);
    }
    final key = encryptionKey ?? List<int>.generate(32, (index) => index);
    await _validateKey(meta, key);
    _cipher = HiveAesCipher(key);
    await _openCommonOrConvergeWipe(meta);
    await _migrateLegacy(meta);
    _initialized = true;
  }

  static Future<void> _validateKey(Box<dynamic> meta, List<int> key) async {
    final verifier = sha256.convert(key).toString();
    final stored = meta.get(_kKeyVerifier);
    if (stored != null && stored != verifier) {
      throw const TranscriptStorageKeyException('key_mismatch');
    }
    if (stored == null) await meta.put(_kKeyVerifier, verifier);
  }

  static Future<void> _openCommonOrConvergeWipe(Box<dynamic> metadata) async {
    if (_transitionGateClosed ||
        metadata.get(_kOwnerTransitionWipePending) == true) {
      await wipeTranscriptsForOwnerTransition();
      return;
    }
    await _openCommonUnchecked();
  }

  static Future<void> _convergePendingOwnerTransitionWipe() async {
    final metadata = Hive.isBoxOpen(_kSecurityMeta)
        ? Hive.box<dynamic>(_kSecurityMeta)
        : await Hive.openBox<dynamic>(_kSecurityMeta);
    if (_transitionGateClosed ||
        metadata.get(_kOwnerTransitionWipePending) == true) {
      await wipeTranscriptsForOwnerTransition();
    }
  }

  static Future<void> _openCommonUnchecked() async {
    await _openEncryptedUnchecked(_kSessionsIndex);
    final runtime = await Hive.openBox<dynamic>(_kRuntime);
    await runtime.clear();
  }

  /// Discard unreadable local transcript ciphertext after explicit confirmation.
  ///
  /// This narrow recovery preserves Owner identity, pairings, preferences, and
  /// mesh state. The pending latch is written only by this method; startup may
  /// resume an already-confirmed deletion but never creates deletion intent in
  /// response to a key error.
  static Future<void> discardUnreadableTranscripts({
    TranscriptKeyValueStore? keyStore,
  }) {
    final inFlight = _transcriptDiscardInFlight;
    if (inFlight != null) return inFlight;
    late final Future<void> tracked;
    tracked = _runTranscriptDiscard(keyStore ?? SecureTranscriptKeyValueStore())
        .whenComplete(() {
          if (identical(_transcriptDiscardInFlight, tracked)) {
            _transcriptDiscardInFlight = null;
          }
        });
    _transcriptDiscardInFlight = tracked;
    return tracked;
  }

  static Future<void> _convergePendingTranscriptDiscard(
    Box<dynamic> metadata,
    TranscriptKeyValueStore keyStore,
  ) async {
    if (metadata.get(_kTranscriptDiscardPending) == true) {
      await _runTranscriptDiscard(keyStore, metadata: metadata);
    }
  }

  static Future<void> _runTranscriptDiscard(
    TranscriptKeyValueStore keyStore, {
    Box<dynamic>? metadata,
  }) async {
    final securityMetadata =
        metadata ??
        (Hive.isBoxOpen(_kSecurityMeta)
            ? Hive.box<dynamic>(_kSecurityMeta)
            : await Hive.openBox<dynamic>(_kSecurityMeta));
    await securityMetadata.put(_kTranscriptDiscardPending, true);

    final targetBoxes = await _recoveryTranscriptBoxNames(securityMetadata);
    for (final name in targetBoxes) {
      if (Hive.isBoxOpen(name)) await Hive.box<dynamic>(name).close();
      if (await Hive.boxExists(name)) await Hive.deleteBoxFromDisk(name);
      await afterTranscriptRecoveryBoxDeleteForTesting?.call(name);
    }

    await keyStore.delete();
    await securityMetadata.delete(_kKeyProvisioned);
    await securityMetadata.delete(_kKeyVerifier);
    await securityMetadata.delete(TranscriptStorageMigrator.copyVerifiedKey);
    await securityMetadata.delete(_kTranscriptDiscardPending);
    _cipher = null;
    _initialized = false;
  }

  static Future<Set<String>> _recoveryTranscriptBoxNames(
    Box<dynamic> metadata,
  ) async {
    final names = <String>{_kSessionsIndex, _kRuntime};
    final metadataPath = metadata.path;
    if (metadataPath == null) return names;
    final home = File(metadataPath).parent;
    if (!await home.exists()) return names;

    await for (final entity in home.list(followLinks: false)) {
      if (entity is! File) continue;
      final fileName = entity.uri.pathSegments.last;
      if (!fileName.endsWith('.hive')) continue;
      final name = fileName.substring(0, fileName.length - '.hive'.length);
      if (name.startsWith('transcript_events_v3_') ||
          name.startsWith('msgs_v3_')) {
        names.add(name);
      }
    }
    return names;
  }

  /// Wipe every transcript-bearing box after a confirmed Owner-key change.
  ///
  /// The operation latches pending state before deletion and keeps transcript
  /// opens gated until every deletion and common-box reopen succeeds. A retry
  /// or cold boot resumes an interrupted wipe before exposing storage.
  static Future<void> wipeTranscriptsForOwnerTransition() {
    final inflight = _wipeInFlight;
    if (inflight != null) return inflight;
    late final Future<void> tracked;
    tracked = _runOwnerTransitionWipe().whenComplete(() {
      if (identical(_wipeInFlight, tracked)) _wipeInFlight = null;
    });
    _wipeInFlight = tracked;
    return tracked;
  }

  static Future<void> _runOwnerTransitionWipe() async {
    _transitionGateClosed = true;
    final metadata = Hive.isBoxOpen(_kSecurityMeta)
        ? Hive.box<dynamic>(_kSecurityMeta)
        : await Hive.openBox<dynamic>(_kSecurityMeta);
    await metadata.put(_kOwnerTransitionWipePending, true);
    await _drainInFlightOpens();
    await beforeOwnerTransitionCommonClearForTesting?.call();

    final index = await _openEncryptedUnchecked(_kSessionsIndex);
    final runtime = await Hive.openBox<dynamic>(_kRuntime);
    final transcriptBoxes = <String>{};
    for (final value in index.values) {
      if (value is! Map) continue;
      try {
        final record = SessionIndexRecord.tryFromJson(
          Map<String, dynamic>.from(value),
        );
        if (record == null) continue;
        transcriptBoxes.add(
          transcriptEventsBoxName(
            TranscriptSessionKey(
              peerId: record.epk,
              roomId: record.roomId,
              sessionId: record.sessionId,
            ),
          ),
        );
        transcriptBoxes.add(msgsBoxName(record.ref));
      } on Object {
        // A malformed index row cannot stop the directory backstop below from
        // deleting any transcript boxes it left behind.
      }
    }

    // Hive 2 does not expose its home directory publicly; the open common
    // index's path is the same directory and remains available on every
    // supported native platform.
    final indexPath = index.path;
    if (indexPath != null) {
      final home = File(indexPath).parent;
      if (await home.exists()) {
        await for (final entity in home.list(followLinks: false)) {
          if (entity is! File) continue;
          final fileName = entity.uri.pathSegments.last;
          if (!fileName.endsWith('.hive')) continue;
          final boxName = fileName.substring(
            0,
            fileName.length - '.hive'.length,
          );
          if (boxName.startsWith('transcript_events_v3_') ||
              boxName.startsWith('msgs_v3_')) {
            transcriptBoxes.add(boxName);
          }
        }
      }
    }

    await index.clear();
    await index.close();
    await runtime.clear();
    await runtime.close();

    for (final name in transcriptBoxes) {
      if (Hive.isBoxOpen(name)) await Hive.box<dynamic>(name).close();
      if (await Hive.boxExists(name)) await Hive.deleteBoxFromDisk(name);
      await afterOwnerTransitionBoxDeleteForTesting?.call(name);
    }
    await _openCommonUnchecked();
    await metadata.delete(_kOwnerTransitionWipePending);
    _transitionGateClosed = false;
  }

  static Future<void> _drainInFlightOpens() {
    if (_inFlightOpens == 0) return Future.value();
    return (_opensDrained ??= Completer<void>()).future;
  }

  static Future<void> _migrateLegacy(Box<dynamic> metadata) async {
    if (TranscriptStorageMigrator.isComplete(metadata)) return;
    final legacySources = await _legacyTranscriptBoxNames();
    if (!await Hive.boxExists(TranscriptStorageMigrator.legacyIndexBoxName)) {
      if (legacySources.isNotEmpty) {
        throw TranscriptMigrationException(
          code: 'unindexed_legacy_source',
          sourceBox: legacySources.first,
        );
      }
      await metadata.delete(TranscriptStorageMigrator.copyVerifiedKey);
      await metadata.put(
        TranscriptStorageMigrator.migrationVersionKey,
        TranscriptStorageMigrator.migrationVersion,
      );
      return;
    }
    final cipher = _cipher;
    if (cipher == null) {
      throw const TranscriptStorageKeyException('key_not_initialized');
    }
    late final Box<dynamic> legacyIndex;
    try {
      legacyIndex = await Hive.openBox<dynamic>(
        TranscriptStorageMigrator.legacyIndexBoxName,
        crashRecovery: false,
      );
    } on Object {
      throw const TranscriptMigrationException(
        code: 'legacy_source_unreadable',
        sourceBox: TranscriptStorageMigrator.legacyIndexBoxName,
      );
    }
    await TranscriptStorageMigrator(cipher: cipher).migrate(
      legacyIndex: legacyIndex,
      secureIndex: Hive.box<dynamic>(_kSessionsIndex),
      metadata: metadata,
      legacySourceNames: legacySources,
    );
  }

  /// Inventory plaintext legacy transcript boxes before migration completion.
  ///
  /// Hive does not expose its home directly, but the encrypted common index
  /// does. Only the two pre-v3 transcript name generations are considered;
  /// v3 boxes share neither plaintext storage nor these exact prefixes.
  static Future<Set<String>> _legacyTranscriptBoxNames() async {
    final index = Hive.box<dynamic>(_kSessionsIndex);
    final indexPath = index.path;
    if (indexPath == null) return const <String>{};
    final home = File(indexPath).parent;
    if (!await home.exists()) return const <String>{};

    final names = <String>{};
    await for (final entity in home.list(followLinks: false)) {
      if (entity is! File) continue;
      final fileName = entity.uri.pathSegments.last;
      if (!fileName.endsWith('.hive')) continue;
      final name = fileName.substring(0, fileName.length - '.hive'.length);
      if ((name.startsWith('transcript_events_') &&
              !name.startsWith('transcript_events_v3_')) ||
          (name.startsWith('msgs_') && !name.startsWith('msgs_v3_'))) {
        names.add(name);
      }
    }
    return names;
  }

  static Future<Box<dynamic>> _openEncrypted(String name) async {
    if (_transitionGateClosed) {
      throw StateError('Owner-transition transcript wipe is pending');
    }
    _inFlightOpens += 1;
    try {
      await beforeTranscriptBoxOpenForTesting?.call(name);
      final box = await _openEncryptedUnchecked(name);
      if (_transitionGateClosed) {
        throw StateError('Owner-transition transcript wipe is pending');
      }
      return box;
    } finally {
      _inFlightOpens -= 1;
      if (_inFlightOpens == 0) {
        final drained = _opensDrained;
        _opensDrained = null;
        if (drained != null && !drained.isCompleted) drained.complete();
      }
    }
  }

  static Future<Box<dynamic>> _openEncryptedUnchecked(String name) async {
    final cipher = _cipher;
    if (cipher == null) {
      throw const TranscriptStorageKeyException('key_not_initialized');
    }
    try {
      return await Hive.openBox<dynamic>(
        name,
        encryptionCipher: cipher,
        crashRecovery: false,
      );
    } on HiveError {
      throw const TranscriptStorageKeyException('encrypted_box_unreadable');
    } on ArgumentError {
      throw const TranscriptStorageKeyException('encrypted_box_unreadable');
    }
  }

  /// Return the encrypted durable cross-session index used by Home projections.
  Box<dynamic> sessionsIndexBox() => Hive.box<dynamic>(_kSessionsIndex);

  /// Return the volatile connection and presence snapshot box.
  Box<dynamic> runtimeBox() => Hive.box<dynamic>(_kRuntime);

  /// Open the encrypted per-session disposable message projection.
  Future<Box<dynamic>> msgsBox(RemoteSessionRef ref) =>
      _openEncrypted(msgsBoxName(ref));

  /// Return an already-open encrypted message projection.
  Box<dynamic> openMsgsBox(RemoteSessionRef ref) =>
      Hive.box<dynamic>(msgsBoxName(ref));

  /// Whether the canonical session's disposable message projection is open.
  bool isMsgsBoxOpen(RemoteSessionRef ref) => Hive.isBoxOpen(msgsBoxName(ref));

  /// Open the encrypted canonical transcript event log.
  Future<Box<dynamic>> transcriptEventsBox(TranscriptSessionKey key) =>
      _openEncrypted(transcriptEventsBoxName(key));

  /// Return an already-open encrypted canonical transcript event log.
  Box<dynamic> openTranscriptEventsBox(TranscriptSessionKey key) =>
      Hive.box<dynamic>(transcriptEventsBoxName(key));

  /// Whether the canonical transcript event log is currently open.
  bool isTranscriptEventsBoxOpen(TranscriptSessionKey key) =>
      Hive.isBoxOpen(transcriptEventsBoxName(key));

  /// Derive the collision-resistant v3 projection box name.
  static String msgsBoxName(RemoteSessionRef ref) =>
      TranscriptBoxIdentity.messagesName(ref);

  /// Derive the collision-resistant v3 canonical event-log box name.
  static String transcriptEventsBoxName(TranscriptSessionKey key) =>
      TranscriptBoxIdentity.eventsName(key);

  /// Derive the shared index key for a canonical remote session.
  static String sessionKey(RemoteSessionRef ref) => ref.storageKey;

  /// Runtime reachability is room-scoped, not transcript-scoped.
  static String runtimeKey(String epk, String roomId) => '$epk:$roomId';
}

// Local transcript storage facade (Hive v3).
//
// Durable transcript-bearing data is encrypted with one platform-secured key:
//   sessions_index_v3                         -> SessionIndexRecord
//   transcript_events_v3_<sha256 tuple>       -> TranscriptEventRecord
//   msgs_v3_<sha256 tuple>                    -> MessageRecord projection
// Runtime reachability remains plaintext and is wiped on every boot.

import 'dart:io';

import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/local/transcript_box_identity.dart';
import 'package:app/data/local/transcript_storage_key.dart';
import 'package:app/data/local/transcript_storage_migration.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';

const String _kNamespace = 'rp_v2';
const String _kSessionsIndex = 'sessions_index_v3';
const String _kRuntime = 'runtime';
const String _kSecurityMeta = TranscriptStorageMigrator.metadataBoxName;
const String _kKeyProvisioned = 'key_provisioned_v3';
const String _kKeyVerifier = 'key_verifier_v3';

/// Facade over encrypted transcript storage and volatile runtime state.
///
/// Production initialization provisions one platform-secured key before any
/// transcript-bearing box opens. Tests inject a fixed key and never call a
/// platform channel.
class LocalBoxes {
  static bool _initialized = false;
  static Future<void>? _initialization;
  static HiveCipher? _cipher;

  /// Open transcript storage and wipe volatile runtime state before bootstrap.
  static Future<void> init({TranscriptKeyValueStore? keyStore}) {
    if (_initialized) return Future.value();
    final inflight = _initialization;
    if (inflight != null) return inflight;
    final future = _initProduction(keyStore);
    _initialization = future;
    return future;
  }

  static Future<void> _initProduction(TranscriptKeyValueStore? keyStore) async {
    await Hive.initFlutter(_kNamespace);
    final meta = await Hive.openBox<dynamic>(_kSecurityMeta);
    final key = await TranscriptStorageKeyManager(
      keyStore ?? SecureTranscriptKeyValueStore(),
    ).loadOrCreate(keyWasProvisioned: meta.get(_kKeyProvisioned) == true);
    await _validateKey(meta, key);
    _cipher = HiveAesCipher(key);
    await _openCommon();
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
  }) async {
    Hive.init(path);
    final key = encryptionKey ?? List<int>.generate(32, (index) => index);
    final meta = await Hive.openBox<dynamic>(_kSecurityMeta);
    await _validateKey(meta, key);
    _cipher = HiveAesCipher(key);
    await _openCommon();
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

  static Future<void> _openCommon() async {
    await _openEncrypted(_kSessionsIndex);
    final runtime = await Hive.openBox<dynamic>(_kRuntime);
    await runtime.clear();
  }

  /// Wipe every transcript-bearing box after a confirmed Owner-key change.
  ///
  /// The stable app key and security metadata remain intact; only the prior
  /// Owner's index, event logs, projections, and volatile runtime state leave
  /// the device. Reopens the common boxes so the router can immediately boot
  /// the replacement Owner against empty storage.
  static Future<void> wipeTranscriptsForOwnerTransition() async {
    final index = Hive.box<dynamic>(_kSessionsIndex);
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
    final runtime = Hive.box<dynamic>(_kRuntime);
    await runtime.clear();
    await runtime.close();

    for (final name in transcriptBoxes) {
      if (Hive.isBoxOpen(name)) await Hive.box<dynamic>(name).close();
      await Hive.deleteBoxFromDisk(name);
    }
    await _openCommon();
  }

  static Future<void> _migrateLegacy(Box<dynamic> metadata) async {
    if (TranscriptStorageMigrator.isComplete(metadata)) return;
    if (!await Hive.boxExists(TranscriptStorageMigrator.legacyIndexBoxName)) {
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
    );
  }

  static Future<Box<dynamic>> _openEncrypted(String name) async {
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

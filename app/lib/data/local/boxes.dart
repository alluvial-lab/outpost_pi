// Local transcript storage facade (Hive v3).
//
// Durable transcript-bearing data is encrypted with one platform-secured key:
//   sessions_index_v3                         -> SessionIndexRecord
//   transcript_events_v3_<sha256 tuple>       -> TranscriptEventRecord
//   msgs_v3_<sha256 tuple>                    -> MessageRecord projection
// Runtime reachability remains plaintext and is wiped on every boot.

import 'package:app/data/local/transcript_box_identity.dart';
import 'package:app/data/local/transcript_storage_key.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';

const String _kNamespace = 'rp_v2';
const String _kSessionsIndex = 'sessions_index_v3';
const String _kRuntime = 'runtime';
const String _kSecurityMeta = 'transcript_security_meta';
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

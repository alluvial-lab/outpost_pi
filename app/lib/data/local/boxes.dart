// Plan/31 — local SSOT box layer (Hive v2).
//
// Three families of box in a NEW namespace (`rp_v2`); v1 (`session_history`,
// the blob snapshot) is abandoned without migration (#6 — re-sync from the Pi
// on first boot). The `runtime` box is VOLATILE: wiped on every boot (#3) so
// connection/presence never report stale online across restarts.
//
//   DERIVED  msgs_<epk>__<roomId>__<sessionId>
//                                           key = seq (int)  → MessageRecord
//            Disposable projection rebuilt from transcript_events.
//
// Peer+room-only boxes from early rp_v2 builds are intentionally not opened or
// deleted here. A clean-room re-sync from the Pi repopulates the active
// canonical `(peer, room, session_id)` box, while rollback can still see the old
// cache files untouched.
//   DURABLE  sessions_index         key = <epk>:<roomId>:<sessionId>
//                                                           → SessionIndexRecord
//   VOLATILE runtime  (wiped@boot)  key = <epk>:<roomId>   → RuntimeRecord

import 'package:app/data/local/transcript_box_identity.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:hive_flutter/hive_flutter.dart';

const String _kNamespace = 'rp_v2';
const String _kSessionsIndex = 'sessions_index';
const String _kRuntime = 'runtime';

/// Facade over the v2 Hive boxes. A single instance is shared by the
/// [SyncService] (writer) and the read repositories (readers) so they observe
/// the same open box objects (`Hive.openBox` is idempotent).
class LocalBoxes {
  static bool _initialized = false;

  /// Open the v2 namespace and the always-on boxes; **wipe `runtime`** before
  /// anything subscribes (#3 / Risk 2). Call once during bootstrap, before
  /// `runApp` and before any read-repo is constructed.
  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter(_kNamespace);
    await _openCommon();
    _initialized = true;
  }

  /// For tests: open against a custom directory. Unlike [init] this always
  /// re-opens + wipes the volatile box, so a second call simulates a restart
  /// (and lets tests assert the wipe).
  static Future<void> initForTest(String path) async {
    if (!_initialized) Hive.init(path);
    await _openCommon();
    _initialized = true;
  }

  static Future<void> _openCommon() async {
    await Hive.openBox<dynamic>(_kSessionsIndex);
    final runtime = await Hive.openBox<dynamic>(_kRuntime);
    await runtime.clear(); // VOLATILE — zero on boot (#3)
  }

  /// Return the durable cross-session index used by Home projections.
  Box<dynamic> sessionsIndexBox() => Hive.box<dynamic>(_kSessionsIndex);

  /// Return the volatile connection and presence snapshot box.
  Box<dynamic> runtimeBox() => Hive.box<dynamic>(_kRuntime);

  /// Per-session message box. Lazily opened; idempotent (returns the already
  /// open box on subsequent calls).
  Future<Box<dynamic>> msgsBox(RemoteSessionRef ref) =>
      Hive.openBox<dynamic>(msgsBoxName(ref));

  /// Synchronous accessor for a msgs box known to be open already.
  Box<dynamic> openMsgsBox(RemoteSessionRef ref) =>
      Hive.box<dynamic>(msgsBoxName(ref));

  /// Whether the canonical session's disposable message projection is open.
  bool isMsgsBoxOpen(RemoteSessionRef ref) => Hive.isBoxOpen(msgsBoxName(ref));

  /// Per canonical transcript session event log. Lazily opened; idempotent.
  Future<Box<dynamic>> transcriptEventsBox(TranscriptSessionKey key) =>
      Hive.openBox<dynamic>(transcriptEventsBoxName(key));

  /// Return an already-open canonical transcript event log.
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

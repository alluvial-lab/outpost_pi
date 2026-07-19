import 'dart:convert';

import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:crypto/crypto.dart';

/// Derive bounded, collision-resistant Hive names for transcript storage.
final class TranscriptBoxIdentity {
  const TranscriptBoxIdentity._();

  /// Hash the canonical transcript tuple while preserving segment boundaries.
  static String digest({
    required String peerId,
    required String roomId,
    required String sessionId,
  }) => sha256
      .convert(utf8.encode(jsonEncode(<String>[peerId, roomId, sessionId])))
      .toString();

  /// Derive the v3 canonical event-log box name.
  static String eventsName(TranscriptSessionKey key) =>
      'transcript_events_v3_${digest(peerId: key.peerId, roomId: key.roomId, sessionId: key.sessionId)}';

  /// Derive the v3 disposable message-projection box name.
  static String messagesName(RemoteSessionRef ref) =>
      'msgs_v3_${digest(peerId: ref.peerId, roomId: ref.roomId, sessionId: ref.sessionId)}';
}

import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/protocol/protocol.dart';

/// Explain whether an inbound server message may affect the active transcript.
///
/// Rejections retain boundary metadata for safe diagnostics without admitting
/// foreign-session content into persistence or UI state.
final class SessionGateDecision {
  const SessionGateDecision._({
    required this.accepted,
    required this.reason,
    this.messageType,
    this.messageSessionId,
    this.expectedSessionId,
  });

  const SessionGateDecision.accepted()
    : this._(accepted: true, reason: 'accepted');

  const SessionGateDecision.rejected({
    required String reason,
    required String messageType,
    String? messageSessionId,
    String? expectedSessionId,
  }) : this._(
         accepted: false,
         reason: reason,
         messageType: messageType,
         messageSessionId: messageSessionId,
         expectedSessionId: expectedSessionId,
       );

  final bool accepted;
  final String reason;
  final String? messageType;
  final String? messageSessionId;
  final String? expectedSessionId;
}

/// Fail closed for server frames whose canonical session differs from active state.
final class SessionGate {
  const SessionGate();

  /// Accept non-session frames, but reject unknown, missing, or mismatched IDs.
  ///
  /// Callers must treat a rejection as a control boundary, not transcript data;
  /// canonical room metadata is the only trusted source for later rebinding.
  SessionGateDecision accepts(ServerMessage message, RemoteSessionRef? active) {
    final messageType = typeOfServerMessage(message);
    if (!isSessionScopedServerType(messageType)) {
      return const SessionGateDecision.accepted();
    }

    final expected = active?.sessionId;
    if (expected == null || expected.isEmpty) {
      return SessionGateDecision.rejected(
        reason: 'active_session_unknown',
        messageType: messageType,
        messageSessionId: sessionIdOfServerMessage(message),
      );
    }

    final actual = sessionIdOfServerMessage(message);
    if (actual == null || actual.isEmpty) {
      return SessionGateDecision.rejected(
        reason: 'missing_session_id',
        messageType: messageType,
        expectedSessionId: expected,
      );
    }

    if (actual != expected) {
      return SessionGateDecision.rejected(
        reason: 'session_mismatch',
        messageType: messageType,
        messageSessionId: actual,
        expectedSessionId: expected,
      );
    }

    return const SessionGateDecision.accepted();
  }
}

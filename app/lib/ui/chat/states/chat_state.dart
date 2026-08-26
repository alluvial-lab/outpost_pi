import 'package:app/domain/session_state.dart';

// Sealed state for ChatViewModel.
// Switch exhaustively in ChatPage.build().

sealed class ChatState {
  const ChatState();
}

// No peer paired yet — show QR scanner redirect.
class ChatNoPeer extends ChatState {
  const ChatNoPeer();
}

// Establishing connection after boot or reconnect.
class ChatConnecting extends ChatState {
  const ChatConnecting();
}

// Connected and ready.
class ChatReady extends ChatState {
  final List<ChatMessage> messages;
  final StreamingMessage? streaming;

  /// Present transport, turn, and steering without flattening their states.
  final ChatStatusProjection status;

  // True once the Mac signalled this device is no longer in peers.json
  // (relay returned an `unknown_peer` error). Stays true until the user
  // re-pairs or revokes; suppresses input and surfaces a re-pair banner.
  final bool pairingRevoked;
  // Set when the Pi sent a `bye` (graceful disconnect). Stops retry,
  // shows banner offering manual reconnect. `peerOfflineReason` is the
  // raw wire reason (peer_stop / session_replaced / shutdown / …).
  final String? peerOfflineReason;

  /// Composer-managed queued text; status presentation derives a steering
  /// overlay from it rather than treating it as an agent phase.
  final String? queuedText;

  /// Local transcript persistence warning; null while writes are healthy.
  final String? persistenceWarning;

  /// True when the server's bounded replay omitted older transcript events.
  final bool historyTruncated;

  const ChatReady({
    required this.messages,
    this.streaming,
    this.status = const ChatStatusProjection(
      transport: ChatTransportOffline(reason: 'Session not connected'),
      turn: AppTurnProjection.stale,
      steering: NoSteering(),
    ),
    this.pairingRevoked = false,
    this.peerOfflineReason,
    this.queuedText,
    this.persistenceWarning,
    this.historyTruncated = false,
  });

  bool get isOffline => status.transport is! ChatTransportOnline;
  bool get isWorking => status.turn.working;

  ChatReady copyWith({
    List<ChatMessage>? messages,
    StreamingMessage? streaming,
    ChatStatusProjection? status,
    bool? pairingRevoked,
    String? peerOfflineReason,
    String? queuedText,
    String? persistenceWarning,
    bool? historyTruncated,
    bool clearStreaming = false,
    bool clearPeerOffline = false,
    bool clearQueuedText = false,
    bool clearPersistenceWarning = false,
  }) => ChatReady(
    messages: messages ?? this.messages,
    streaming: clearStreaming ? null : (streaming ?? this.streaming),
    status: status ?? this.status,
    pairingRevoked: pairingRevoked ?? this.pairingRevoked,
    peerOfflineReason: clearPeerOffline
        ? null
        : (peerOfflineReason ?? this.peerOfflineReason),
    queuedText: clearQueuedText ? null : (queuedText ?? this.queuedText),
    persistenceWarning: clearPersistenceWarning
        ? null
        : (persistenceWarning ?? this.persistenceWarning),
    historyTruncated: historyTruncated ?? this.historyTruncated,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatReady &&
      other.messages == messages &&
      other.streaming == streaming &&
      other.status == status &&
      other.pairingRevoked == pairingRevoked &&
      other.peerOfflineReason == peerOfflineReason &&
      other.queuedText == queuedText &&
      other.persistenceWarning == persistenceWarning &&
      other.historyTruncated == historyTruncated;

  @override
  int get hashCode => Object.hash(
    messages,
    streaming,
    status,
    pairingRevoked,
    peerOfflineReason,
    queuedText,
    persistenceWarning,
    historyTruncated,
  );
}

/// A recoverable failure while loading or rebinding the selected session.
final class ChatInitializationFailed extends ChatState {
  const ChatInitializationFailed(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is ChatInitializationFailed && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

// Permanent offline — must re-pair.
class ChatFatalError extends ChatState {
  final String message;
  const ChatFatalError(this.message);

  @override
  bool operator ==(Object other) =>
      other is ChatFatalError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

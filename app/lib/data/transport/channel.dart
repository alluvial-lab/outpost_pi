import 'package:app/protocol/protocol.dart';

/// Attribute the first event that made a channel unusable.
enum ChannelCloseOrigin {
  serverCloseFrame,
  streamError,
  streamDone,
  localClose,
  unknown,
}

/// Name locally initiated close paths without retaining free-form labels.
enum ChannelLocalClosePath {
  unspecified,
  connectCancellation,
  connectFailureCleanup,
  managerAdoptReplacement,
  managerDisconnect,
  managerDispose,
  managerConnectReplacement,
  connectSupersededAfterFactory,
  connectLateCompletion,
  hedgeLoser,
  secureOutboundOverflow,
  secureSequenceExhausted,
  securePersistenceFailure,
  secureInvalidFrameThreshold,
  secureTransportCleanup,
}

/// Carry content-free WebSocket closure evidence through channel adapters.
final class ChannelCloseDetails {
  const ChannelCloseDetails({
    required this.origin,
    this.closeCode,
    this.closeReason,
    this.localPath,
    this.errorType,
  });

  final ChannelCloseOrigin origin;
  final int? closeCode;
  final String? closeReason;
  final ChannelLocalClosePath? localPath;
  final String? errorType;

  @override
  bool operator ==(Object other) =>
      other is ChannelCloseDetails &&
      other.origin == origin &&
      other.closeCode == closeCode &&
      other.closeReason == closeReason &&
      other.localPath == localPath &&
      other.errorType == errorType;

  @override
  int get hashCode =>
      Object.hash(origin, closeCode, closeReason, localPath, errorType);
}

/// Expose causative close evidence and path-attributed local teardown.
abstract interface class IChannelCloseDiagnostics {
  /// Return the first recorded close cause, or null while the channel is live.
  ChannelCloseDetails? get closeDetails;

  /// Close locally while recording the owning lifecycle path.
  Future<void> closeWithPath(ChannelLocalClosePath path);
}

/// Expose content-free inbound frame-hash evidence for connection-loss logs.
abstract interface class IInboundFrameHashDiagnostics {
  /// Number of application data messages delivered on this connection.
  int get inboundFrameCount;

  /// Running FNV-1a64 hash at the latest delivered message.
  String get inboundHash;
}

/// Exchange typed app/Pi messages while exposing explicit stream ownership.
///
/// The channel owner must call [close] to release the underlying transport and
/// terminate [serverMessages].
abstract class IChannel {
  /// Emit decoded Pi messages until transport closure or stream failure.
  Stream<ServerMessage> get serverMessages;

  /// Send one typed client message; completes only after transport acceptance.
  Future<void> send(ClientMessage msg);

  /// Release transport resources and close all channel-facing streams.
  Future<void> close();
}

/// Optionally retarget peer envelopes to a different Pi room.
///
/// Channels and byte transports without room-aware routing remain valid and
/// callers must treat the capability as a no-op when it is absent.
abstract interface class IActiveRoomTarget {
  /// Route subsequent peer envelopes to [roomId].
  void setActiveRoom(String roomId);
}

/// Optionally exchange raw relay control frames beside typed peer messages.
///
/// [ConnectionManager] uses this capability for presence and room hydration;
/// channels without it remain valid peer-message channels.
abstract class IControlLink {
  /// Emit validated relay control frames for presence and room state.
  Stream<ControlInbound> get controlFrames;

  /// Send one relay control frame without routing it through peer envelopes.
  void sendControl(Map<String, dynamic> json);
}

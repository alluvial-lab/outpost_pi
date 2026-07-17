import 'package:app/protocol/protocol.dart';

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

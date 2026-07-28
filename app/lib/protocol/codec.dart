import 'dart:convert';

import 'protocol.dart';

String encodeClient(ClientMessage m) => '${jsonEncode(m.toJson())}\n';

/// A typed server message plus wire-presence metadata needed by compatibility
/// consumers.
final class DecodedServerMessage {
  const DecodedServerMessage({
    required this.message,
    required this.hasRoomId,
  });

  final ServerMessage message;
  final bool hasRoomId;
}

/// Decode an untrusted server frame through the generated message registry.
DecodedServerMessage decodeServerFrame(String line) {
  final raw = jsonDecode(line);
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('Server frame must be a JSON object');
  }
  return DecodedServerMessage(
    message: ServerMessage.fromJson(raw),
    hasRoomId: raw.containsKey('room_id'),
  );
}

/// Decode an untrusted server frame into its generated message variant.
ServerMessage decodeServer(String line) => decodeServerFrame(line).message;

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/protocol/protocol.dart';

/// Typed relay frame exposed to the WebSocket transport after boundary parsing.
sealed class RelayInboundFrameDto {
  const RelayInboundFrameDto();
}

/// Relay outer envelope carrying one base64 app↔Pi payload.
final class RelayOuterEnvelopeDto extends RelayInboundFrameDto {
  final String peer;
  final String? room;
  final String ct;

  const RelayOuterEnvelopeDto({
    required this.peer,
    required this.room,
    required this.ct,
  });
}

/// Relay control frame adapted into the app's existing control-domain contract.
final class RelayControlFrameDto extends RelayInboundFrameDto {
  final String type;
  final ControlInbound control;

  const RelayControlFrameDto({required this.type, required this.control});
}

/// Stable rejection categories for payload-free transport diagnostics.
enum RelayFrameDecodeFailure { malformed, unsupportedType }

/// Result of classifying one authenticated relay frame.
sealed class RelayFrameDecodeResult {
  const RelayFrameDecodeResult();
}

/// Validated relay frame and the decoded outer payload when applicable.
final class DecodedRelayFrame extends RelayFrameDecodeResult {
  final RelayInboundFrameDto frame;
  final Uint8List? decodedPayload;

  const DecodedRelayFrame({required this.frame, this.decodedPayload});
}

/// Content-free boundary rejection.
final class RejectedRelayFrame extends RelayFrameDecodeResult {
  final RelayFrameDecodeFailure reason;
  final int observedSize;

  const RejectedRelayFrame({required this.reason, required this.observedSize});
}

/// Parse one relay frame into typed outer/control DTOs before transport routing.
RelayFrameDecodeResult decodeRelayInboundFrame(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return RejectedRelayFrame(
        reason: RelayFrameDecodeFailure.malformed,
        observedSize: raw.length,
      );
    }

    final peer = decoded['peer'];
    final ct = decoded['ct'];
    if (peer is String && peer.isNotEmpty && ct is String && ct.isNotEmpty) {
      final room = decoded['room'];
      if (room != null && room is! String) {
        return RejectedRelayFrame(
          reason: RelayFrameDecodeFailure.malformed,
          observedSize: raw.length,
        );
      }
      return DecodedRelayFrame(
        frame: RelayOuterEnvelopeDto(peer: peer, room: room as String?, ct: ct),
        decodedPayload: decodeRelayBase64(ct),
      );
    }

    final type = decoded['type'];
    if (type is! String) {
      return RejectedRelayFrame(
        reason: RelayFrameDecodeFailure.malformed,
        observedSize: raw.length,
      );
    }
    final control = ControlInbound.tryFromJson(decoded);
    return control == null
        ? RejectedRelayFrame(
            reason: RelayFrameDecodeFailure.unsupportedType,
            observedSize: raw.length,
          )
        : DecodedRelayFrame(
            frame: RelayControlFrameDto(type: type, control: control),
          );
  } on Object {
    return RejectedRelayFrame(
      reason: RelayFrameDecodeFailure.malformed,
      observedSize: raw.length,
    );
  }
}

/// Decode standard or URL-safe base64 retained for current peer compatibility.
Uint8List decodeRelayBase64(String value) {
  final pad = (4 - value.length % 4) % 4;
  final padded = value + '=' * pad;
  try {
    return base64.decode(padded);
  } on FormatException {
    return base64Url.decode(padded);
  }
}

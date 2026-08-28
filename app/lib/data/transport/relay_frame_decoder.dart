import 'dart:convert';
import 'dart:typed_data';

import 'package:app/protocol/protocol.dart';

/// Stable rejection categories for payload-free transport diagnostics.
enum RelayFrameDecodeFailure { tooLarge, malformed, unsupportedType }

/// Result of classifying one authenticated relay frame.
sealed class RelayFrameDecodeResult {
  const RelayFrameDecodeResult();
}

/// Validated relay frame and the decoded outer payload when applicable.
final class DecodedRelayFrame extends RelayFrameDecodeResult {
  final RelayInboundFrameDto frame;
  final Uint8List? decodedPayload;
  final ControlInbound? control;

  const DecodedRelayFrame({
    required this.frame,
    this.decodedPayload,
    this.control,
  });
}

/// Content-free boundary rejection.
final class RejectedRelayFrame extends RelayFrameDecodeResult {
  final RelayFrameDecodeFailure reason;
  final int observedSize;

  const RejectedRelayFrame({required this.reason, required this.observedSize});
}

/// Content-free pre-auth decode failure.
final class RelayFrameDecodeException implements Exception {
  final RelayFrameDecodeFailure reason;
  final int observedSize;

  const RelayFrameDecodeException(this.reason, this.observedSize);

  @override
  String toString() =>
      'RelayFrameDecodeException: ${reason.name} '
      '($observedSize bytes)';
}

/// Count UTF-8 bytes without allocating an attacker-sized encoded copy.
///
/// Returns as soon as [maxBytes] is crossed, so callers can reject before JSON
/// parsing while still handling UTF-16 surrogate pairs consistently with UTF-8.
int relayUtf8ByteLength(String value, {int maxBytes = 0x7fffffffffffffff}) {
  var bytes = 0;
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit <= 0x7f) {
      bytes += 1;
    } else if (unit <= 0x7ff) {
      bytes += 2;
    } else if (unit >= 0xd800 &&
        unit <= 0xdbff &&
        i + 1 < value.length &&
        value.codeUnitAt(i + 1) >= 0xdc00 &&
        value.codeUnitAt(i + 1) <= 0xdfff) {
      bytes += 4;
      i += 1;
    } else {
      // A BMP scalar or malformed unpaired surrogate is encoded as three bytes.
      bytes += 3;
    }
    if (bytes > maxBytes) return bytes;
  }
  return bytes;
}

/// Parse one relay frame into typed outer/control DTOs before transport routing.
RelayFrameDecodeResult decodeRelayInboundFrame(
  String raw, {
  int maxRawBytes = relayMaxRawMessageBytes,
  int maxDecodedPayloadBytes = relayDefaultMaxDecodedBytes,
}) {
  final rawBytes = relayUtf8ByteLength(raw, maxBytes: maxRawBytes);
  if (rawBytes > maxRawBytes) {
    return RejectedRelayFrame(
      reason: RelayFrameDecodeFailure.tooLarge,
      observedSize: rawBytes,
    );
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return RejectedRelayFrame(
        reason: RelayFrameDecodeFailure.malformed,
        observedSize: rawBytes,
      );
    }

    final frame = RelayInboundFrameDto.fromJson(decoded);
    return switch (frame) {
      RelayOuterEnvelopeDto(:final ct) => DecodedRelayFrame(
        frame: frame,
        decodedPayload: decodeRelayBase64(
          ct,
          maxDecodedBytes: maxDecodedPayloadBytes,
        ),
      ),
      RelayServerControlFrameDto() => () {
        final control = ControlInbound.fromWire(frame, raw: decoded);
        return control == null
            ? RejectedRelayFrame(
                reason: RelayFrameDecodeFailure.unsupportedType,
                observedSize: rawBytes,
              )
            : DecodedRelayFrame(frame: frame, control: control);
      }(),
    };
  } on RelayFrameDecodeException catch (error) {
    return RejectedRelayFrame(
      reason: error.reason,
      observedSize: error.observedSize,
    );
  } on Object {
    return RejectedRelayFrame(
      reason: RelayFrameDecodeFailure.malformed,
      observedSize: rawBytes,
    );
  }
}

/// Decode one pre-auth challenge after enforcing its smaller raw-frame ceiling.
Uint8List decodeRelayChallenge(String raw) {
  final rawBytes = relayUtf8ByteLength(
    raw,
    maxBytes: relayMaxPreAuthFrameBytes,
  );
  if (rawBytes > relayMaxPreAuthFrameBytes) {
    throw RelayFrameDecodeException(RelayFrameDecodeFailure.tooLarge, rawBytes);
  }

  try {
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) {
      throw RelayFrameDecodeException(
        RelayFrameDecodeFailure.malformed,
        rawBytes,
      );
    }
    final frame = RelayServerControlFrameDto.fromJson(json);
    if (frame is! RelayChallengeFrameDto) {
      throw RelayFrameDecodeException(
        RelayFrameDecodeFailure.malformed,
        rawBytes,
      );
    }
    final nonce = decodeRelayBase64(frame.nonce, maxDecodedBytes: 32);
    if (nonce.length != 32) {
      throw RelayFrameDecodeException(
        RelayFrameDecodeFailure.malformed,
        nonce.length,
      );
    }
    return nonce;
  } on RelayFrameDecodeException {
    rethrow;
  } on Object {
    throw RelayFrameDecodeException(
      RelayFrameDecodeFailure.malformed,
      rawBytes,
    );
  }
}

/// Decode standard or URL-safe base64 after checking encoded and decoded limits.
Uint8List decodeRelayBase64(
  String value, {
  int maxDecodedBytes = relayDefaultMaxDecodedBytes,
}) {
  final maxEncodedBytes = 4 * ((maxDecodedBytes + 2) ~/ 3);
  if (value.length > maxEncodedBytes) {
    throw RelayFrameDecodeException(
      RelayFrameDecodeFailure.tooLarge,
      value.length,
    );
  }
  if (value.length % 4 == 1 ||
      !RegExp(r'^[A-Za-z0-9+/_-]*={0,2}$').hasMatch(value)) {
    throw RelayFrameDecodeException(
      RelayFrameDecodeFailure.malformed,
      value.length,
    );
  }

  final pad = (4 - value.length % 4) % 4;
  final padded = value + '=' * pad;
  late final Uint8List decoded;
  try {
    decoded = base64.decode(padded);
  } on FormatException {
    try {
      decoded = base64Url.decode(padded);
    } on FormatException {
      throw RelayFrameDecodeException(
        RelayFrameDecodeFailure.malformed,
        value.length,
      );
    }
  }
  if (decoded.length > maxDecodedBytes) {
    throw RelayFrameDecodeException(
      RelayFrameDecodeFailure.tooLarge,
      decoded.length,
    );
  }
  return decoded;
}

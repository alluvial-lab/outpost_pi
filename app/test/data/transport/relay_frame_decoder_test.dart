import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/transport/relay_frame_decoder.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

String _outerFrame(List<int> payload) => jsonEncode({
  'peer': 'peer-a',
  'room': 'room-a',
  'ct': base64Encode(payload),
});

Matcher _rejectedFor(RelayFrameDecodeFailure reason) =>
    isA<RejectedRelayFrame>().having(
      (result) => result.reason,
      'reason',
      reason,
    );

Matcher _throwsDecodeFailure(RelayFrameDecodeFailure reason) => throwsA(
  isA<RelayFrameDecodeException>().having(
    (error) => error.reason,
    'reason',
    reason,
  ),
);

void main() {
  group('bounded relay ingress', () {
    test('multibyte raw input crosses the UTF-8 limit before JSON parsing', () {
      final result = decodeRelayInboundFrame('é{', maxRawBytes: 2);

      expect(result, _rejectedFor(RelayFrameDecodeFailure.tooLarge));
      expect((result as RejectedRelayFrame).observedSize, 3);
    });

    test('accepts the exact decoded boundary and rejects encoded overage', () {
      final exact = decodeRelayInboundFrame(
        _outerFrame([1, 2, 3]),
        maxDecodedPayloadBytes: 3,
      );
      final over = decodeRelayInboundFrame(
        _outerFrame([1, 2, 3, 4]),
        maxDecodedPayloadBytes: 3,
      );

      expect(exact, isA<DecodedRelayFrame>());
      expect(
        (exact as DecodedRelayFrame).decodedPayload,
        orderedEquals([1, 2, 3]),
      );
      expect(over, _rejectedFor(RelayFrameDecodeFailure.tooLarge));
      expect((over as RejectedRelayFrame).observedSize, 8);
    });

    test(
      'checks decoded length after an encoded payload passes its ceiling',
      () {
        final result = decodeRelayInboundFrame(
          _outerFrame([1, 2]),
          maxDecodedPayloadBytes: 1,
        );

        expect(result, _rejectedFor(RelayFrameDecodeFailure.tooLarge));
        expect((result as RejectedRelayFrame).observedSize, 2);
      },
    );
  });

  group('bounded pre-auth challenge', () {
    test(
      'rejects raw input above the pre-auth ceiling before JSON parsing',
      () {
        final raw = List.filled(relayMaxPreAuthFrameBytes + 1, 'x').join();

        expect(
          () => decodeRelayChallenge(raw),
          _throwsDecodeFailure(RelayFrameDecodeFailure.tooLarge),
        );
      },
    );

    test('rejects wrong frame types and non-32-byte nonces', () {
      expect(
        () => decodeRelayChallenge(
          jsonEncode({'type': 'peer_online', 'peer': 'peer-a'}),
        ),
        _throwsDecodeFailure(RelayFrameDecodeFailure.malformed),
      );

      for (final (length, reason) in [
        (31, RelayFrameDecodeFailure.malformed),
        (33, RelayFrameDecodeFailure.tooLarge),
      ]) {
        expect(
          () => decodeRelayChallenge(
            jsonEncode({
              'type': 'challenge',
              'nonce': base64Encode(Uint8List(length)),
            }),
          ),
          _throwsDecodeFailure(reason),
          reason: '$length-byte challenge nonces are non-canonical',
        );
      }
    });

    test('accepts a canonical 32-byte challenge nonce', () {
      final nonce = Uint8List.fromList(List.generate(32, (index) => index));
      final decoded = decodeRelayChallenge(
        jsonEncode({'type': 'challenge', 'nonce': base64Encode(nonce)}),
      );

      expect(decoded, orderedEquals(nonce));
    });
  });
}

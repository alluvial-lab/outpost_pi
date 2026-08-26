import 'package:app/pairing/qr_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QrPairPayload.tryParse', () {
    const goodToken = 'AAAAAAAAAAAAAAAAAAAAAA'; // 16 bytes base64url
    const goodEpk = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'; // 32 bytes
    const sessionName = 'test+session';

    String link(String parameters) => '$kPairLinkPrefix$parameters';

    test('parses the verified HTTPS link without a relay parameter', () {
      final qr = QrPairPayload.tryParse(
        link('t=$goodToken&epk=$goodEpk&n=$sessionName'),
      );
      expect(qr, isNotNull);
      expect(qr!.token, goodToken);
      expect(qr.epk, goodEpk);
      expect(qr.sessionName, 'test session');
      expect(qr.relayUrl, isNull);
    });

    test('parses a legacy relay parameter inside the protected fragment', () {
      final qr = QrPairPayload.tryParse(
        link(
          't=$goodToken&epk=$goodEpk&'
          'r=ws%3A%2F%2Flocalhost&n=$sessionName',
        ),
      );
      expect(qr, isNotNull);
      expect(qr!.relayUrl, 'ws://localhost');
    });

    test('rejects a custom-scheme link even when its payload is valid', () {
      final raw = 'outpostpi://pair?t=$goodToken&epk=$goodEpk&n=$sessionName';
      expect(QrPairPayload.tryParse(raw), isNull);
    });

    test('rejects an unverified HTTPS origin and path lookalikes', () {
      final parameters = 't=$goodToken&epk=$goodEpk&n=$sessionName';
      expect(
        QrPairPayload.tryParse('https://example.com/pair#$parameters'),
        isNull,
      );
      expect(
        QrPairPayload.tryParse('$kPairLinkOrigin/pairing#$parameters'),
        isNull,
      );
    });

    test('rejects enrollment parameters in the HTTP query', () {
      final raw =
          '$kPairLinkOrigin$kPairLinkPath?'
          't=$goodToken&epk=$goodEpk&n=$sessionName';
      expect(QrPairPayload.tryParse(raw), isNull);
    });

    test('rejects when t is missing or has the wrong length', () {
      expect(
        QrPairPayload.tryParse(link('epk=$goodEpk&n=$sessionName')),
        isNull,
      );
      expect(
        QrPairPayload.tryParse(link('t=AAAA&epk=$goodEpk&n=$sessionName')),
        isNull,
      );
    });

    test('rejects when epk has the wrong byte length', () {
      expect(
        QrPairPayload.tryParse(
          link('t=$goodToken&epk=AAAAAAAAA&n=$sessionName'),
        ),
        isNull,
      );
    });

    test('empty r is treated as null', () {
      final qr = QrPairPayload.tryParse(
        link('t=$goodToken&epk=$goodEpk&r=&n=$sessionName'),
      );
      expect(qr, isNotNull);
      expect(qr!.relayUrl, isNull);
    });

    test('parses the Pi room id used for the first pair request', () {
      final qr = QrPairPayload.tryParse(
        link('t=$goodToken&epk=$goodEpk&rm=abc123def456&n=$sessionName'),
      );
      expect(qr, isNotNull);
      expect(qr!.roomId, 'abc123def456');
    });

    test('missing or empty room id remains backward compatible', () {
      final withoutRoom = QrPairPayload.tryParse(
        link('t=$goodToken&epk=$goodEpk&n=$sessionName'),
      );
      final emptyRoom = QrPairPayload.tryParse(
        link('t=$goodToken&epk=$goodEpk&rm=&n=$sessionName'),
      );
      expect(withoutRoom, isNotNull);
      expect(withoutRoom!.roomId, isNull);
      expect(emptyRoom, isNotNull);
      expect(emptyRoom!.roomId, isNull);
    });

    test('tolerates surrounding whitespace and trailing newlines', () {
      final raw = link('t=$goodToken&epk=$goodEpk&n=$sessionName');
      expect(QrPairPayload.tryParse('  $raw  '), isNotNull);
      expect(QrPairPayload.tryParse('\n$raw\n'), isNotNull);
    });

    test('tolerates surrounding quote characters', () {
      final raw = link('t=$goodToken&epk=$goodEpk&n=$sessionName');
      expect(QrPairPayload.tryParse('"$raw"'), isNotNull);
      expect(QrPairPayload.tryParse("'$raw'"), isNotNull);
    });
  });
}

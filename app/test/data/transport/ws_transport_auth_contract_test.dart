import 'dart:convert';
import 'dart:io';

import 'package:app/data/transport/ws_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('relay auth signs the shared cross-component byte vector', () {
    final vector =
        jsonDecode(
              File(
                '../protocol/fixtures/relay/auth-domain-vector.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final authDomainPrefix = vector['authDomainPrefix'] as String;
    final nonce = base64.decode(vector['nonceBase64'] as String);
    final signingBytes = base64.decode(vector['signingBytesBase64'] as String);

    expect(relayAuthDomainPrefix, orderedEquals(utf8.encode(authDomainPrefix)));
    expect(relayAuthSigningBytes(nonce), orderedEquals(signingBytes));
  });
}

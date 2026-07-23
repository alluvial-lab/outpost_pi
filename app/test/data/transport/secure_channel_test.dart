import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/data/transport/secure_channel.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _b64(String value) => Uint8List.fromList(base64.decode(value));

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  late Map<String, dynamic> kat;

  setUpAll(() async {
    kat =
        jsonDecode(
              await File(
                '../protocol/fixtures/app-pi/owner-channel-kat.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
  });

  test(
    'reproduces the cross-language known-answer vector byte-for-byte',
    () async {
      expect(kat['suite'], ownerChannelSuite);
      final appSecret = _b64(kat['app_dh_sk'] as String);
      final piSecret = _b64(kat['pi_dh_sk'] as String);
      final appPublic = _b64(kat['app_dh_pk'] as String);
      final piPublic = _b64(kat['pi_dh_pk'] as String);
      final ownerPublic = _b64(kat['owner_ed_pk'] as String);
      final piEdPublic = _b64(kat['pi_ed_pk'] as String);
      final token = kat['token'] as String;

      final shared = await deriveOwnerChannelSharedSecret(appSecret, piPublic);
      final peerShared = await deriveOwnerChannelSharedSecret(
        piSecret,
        appPublic,
      );
      expect(base64.encode(shared), kat['shared_secret']);
      expect(peerShared, shared);

      final appKeys = await deriveOwnerChannelKeys(
        sharedSecret: shared,
        token: token,
        side: OwnerChannelSide.app,
      );
      final piKeys = await deriveOwnerChannelKeys(
        sharedSecret: peerShared,
        token: token,
        side: OwnerChannelSide.pi,
      );
      expect(base64.encode(appKeys.send), kat['k_app_to_pi']);
      expect(base64.encode(appKeys.receive), kat['k_pi_to_app']);
      expect(piKeys.receive, appKeys.send);
      expect(piKeys.send, appKeys.receive);

      final appTranscript = buildAppOwnerChannelTranscript(
        token: token,
        appDhPublicKey: appPublic,
        piEdPublicKey: piEdPublic,
      );
      final piTranscript = buildPiOwnerChannelTranscript(
        token: token,
        appDhPublicKey: appPublic,
        piDhPublicKey: piPublic,
        ownerEdPublicKey: ownerPublic,
      );
      expect(_hex(appTranscript), kat['app_transcript_hex']);
      expect(_hex(piTranscript), kat['pi_transcript_hex']);
      expect(
        await Ed25519().verify(
          appTranscript,
          signature: Signature(
            _b64(kat['app_dh_sig'] as String),
            publicKey: SimplePublicKey(ownerPublic, type: KeyPairType.ed25519),
          ),
        ),
        isTrue,
      );
      expect(
        await Ed25519().verify(
          piTranscript,
          signature: Signature(
            _b64(kat['pi_dh_sig'] as String),
            publicKey: SimplePublicKey(piEdPublic, type: KeyPairType.ed25519),
          ),
        ),
        isTrue,
      );

      final frames = (kat['frames'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (final vector in frames) {
        final key = vector['dir'] == 'app->pi' ? appKeys.send : appKeys.receive;
        final sequence = vector['seq'] as int;
        final sealed = await sealOwnerChannelFrame(
          key: key,
          sequence: sequence,
          json: vector['plaintext_json'] as String,
          nonce: _b64(vector['nonce'] as String),
        );
        expect(base64.encode(sealed), vector['sealed_b64']);

        final opened = await openOwnerChannelFrame(
          key: key,
          frame: sealed,
          lastSequence: sequence - 1,
        );
        expect(opened?.sequence, sequence);
        expect(opened?.json, vector['plaintext_json']);
      }
    },
  );

  test('returns null for tamper, replay, and wrong frame version', () async {
    final key = _b64(kat['k_app_to_pi'] as String);
    final vector =
        (kat['frames'] as List<dynamic>).first as Map<String, dynamic>;
    final frame = _b64(vector['sealed_b64'] as String);

    final tampered = Uint8List.fromList(frame)..[frame.length - 1] ^= 1;
    expect(
      await openOwnerChannelFrame(key: key, frame: tampered, lastSequence: 0),
      isNull,
    );
    expect(
      await openOwnerChannelFrame(key: key, frame: frame, lastSequence: 1),
      isNull,
    );
    final wrongVersion = Uint8List.fromList(frame)..[0] = 2;
    expect(
      await openOwnerChannelFrame(
        key: key,
        frame: wrongVersion,
        lastSequence: 0,
      ),
      isNull,
    );
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/data/transport/relay_config.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:cryptography/cryptography.dart';

/// Test-only authenticated relay client for injecting owner envelopes.
final class RawOwnerRelayClient {
  RawOwnerRelayClient._(this._socket, this._subscription, this._frames);

  static Future<RawOwnerRelayClient> connect({
    required Uri relay,
    required SimpleKeyPair ownerKey,
    required String deviceId,
  }) async {
    final socket = await WebSocket.connect(toWsRelayUrl(relay.toString()));
    final frames = <Map<String, dynamic>>[];
    final challenge = Completer<Map<String, dynamic>>();
    var authenticated = false;
    final subscription = socket.listen((Object? raw) {
      final decoded = jsonDecode(raw! as String) as Map<String, dynamic>;
      if (!authenticated && decoded['type'] == 'challenge') {
        if (!challenge.isCompleted) challenge.complete(decoded);
        return;
      }
      frames.add(decoded);
    });

    final publicKey = await ownerKey.extractPublicKey();
    socket.add(
      jsonEncode(<String, Object>{
        'type': 'hello',
        'pubkey': base64.encode(publicKey.bytes),
        'device_id': deviceId,
        'room_id': 'main',
      }),
    );
    final challengeFrame = await challenge.future.timeout(
      const Duration(seconds: 5),
    );
    final nonce = base64.decode(challengeFrame['nonce']! as String);
    final signature = await Ed25519().sign(
      relayAuthSigningBytes(nonce),
      keyPair: ownerKey,
    );
    authenticated = true;
    socket.add(
      jsonEncode(<String, Object>{
        'type': 'auth',
        'sig': base64.encode(signature.bytes),
      }),
    );
    return RawOwnerRelayClient._(socket, subscription, frames);
  }

  final WebSocket _socket;
  final StreamSubscription<Object?> _subscription;
  final List<Map<String, dynamic>> _frames;

  int get deliveredEnvelopeCount => _frames.where(_isEnvelope).length;

  /// Inject one opaque owner payload toward the Pi's authenticated room.
  void inject({
    required String piPublicKey,
    required String piRoomId,
    required List<int> payload,
  }) {
    _socket.add(
      jsonEncode(<String, Object>{
        'peer': _standardBase64(piPublicKey),
        'room': piRoomId,
        'ct': base64.encode(Uint8List.fromList(payload)),
      }),
    );
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _socket.close();
  }

  static bool _isEnvelope(Map<String, dynamic> frame) =>
      frame['peer'] is String && frame['ct'] is String;

  static String _standardBase64(String value) {
    final padded = value + '=' * ((4 - value.length % 4) % 4);
    return base64.encode(base64Url.decode(padded));
  }
}

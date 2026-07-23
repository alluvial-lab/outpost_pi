import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Domain separator for the authenticated app-to-Pi owner channel.
const ownerChannelSuite = 'outpost-pi-owner-channel-v1';

const int _frameVersion = 0x01;
const int _nonceLength = 24;
const int _macLength = 16;
const int _keyLength = 32;
// Dart native integers are signed 64-bit. Exhaust at the positive boundary;
// reaching it would require centuries of sustained traffic and failing closed is
// safer than relying on a negative two's-complement representation.
const int _maxSequence = 0x7fffffffffffffff;

/// Identify which endpoint owns a derived pair of directional channel keys.
enum OwnerChannelSide { app, pi }

/// Hold send and receive keys in the endpoint's local direction.
final class DirectionalKeys {
  DirectionalKeys({required List<int> send, required List<int> receive})
    : send = Uint8List.fromList(send),
      receive = Uint8List.fromList(receive) {
    if (this.send.length != _keyLength || this.receive.length != _keyLength) {
      throw ArgumentError('owner-channel keys must be 32 bytes');
    }
  }

  final Uint8List send;
  final Uint8List receive;
}

/// Hold an extractable ephemeral X25519 keypair for one pairing attempt.
final class OwnerChannelKeyPair {
  OwnerChannelKeyPair({
    required List<int> publicKey,
    required List<int> secretKey,
  }) : publicKey = Uint8List.fromList(publicKey),
       secretKey = Uint8List.fromList(secretKey) {
    if (this.publicKey.length != _keyLength ||
        this.secretKey.length != _keyLength) {
      throw ArgumentError('X25519 keys must be 32 bytes');
    }
  }

  final Uint8List publicKey;
  final Uint8List secretKey;
}

/// Return a successfully opened frame and its authenticated sequence number.
final class OpenedOwnerFrame {
  const OpenedOwnerFrame({required this.sequence, required this.json});

  final int sequence;
  final String json;
}

final _x25519 = X25519();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: _keyLength);
final _cipher = Cryptography.instance.xchacha20Poly1305Aead();

/// Generate a fresh ephemeral X25519 keypair.
Future<OwnerChannelKeyPair> generateOwnerChannelKeyPair() async {
  final keyPair = await _x25519.newKeyPair();
  try {
    final publicKey = await keyPair.extractPublicKey();
    final secretKey = await keyPair.extractPrivateKeyBytes();
    return OwnerChannelKeyPair(
      publicKey: publicKey.bytes,
      secretKey: secretKey,
    );
  } finally {
    keyPair.destroy();
  }
}

/// Derive the X25519 shared secret from a local secret and remote public key.
Future<Uint8List> deriveOwnerChannelSharedSecret(
  List<int> secretKey,
  List<int> remotePublicKey,
) async {
  _requireLength(secretKey, _keyLength, 'X25519 secret key');
  _requireLength(remotePublicKey, _keyLength, 'X25519 public key');
  final keyPair = await _x25519.newKeyPairFromSeed(secretKey);
  try {
    final shared = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(
        remotePublicKey,
        type: KeyPairType.x25519,
      ),
    );
    return Uint8List.fromList(await shared.extractBytes());
  } finally {
    keyPair.destroy();
  }
}

/// Derive domain-separated directional keys using RFC 5869 HKDF-SHA256.
Future<DirectionalKeys> deriveOwnerChannelKeys({
  required List<int> sharedSecret,
  required String token,
  required OwnerChannelSide side,
}) async {
  _requireLength(sharedSecret, _keyLength, 'X25519 shared secret');
  final tokenBytes = utf8.encode(token);
  final appToPi = await _deriveDirection(
    sharedSecret,
    tokenBytes,
    '$ownerChannelSuite\napp->pi',
  );
  final piToApp = await _deriveDirection(
    sharedSecret,
    tokenBytes,
    '$ownerChannelSuite\npi->app',
  );
  return switch (side) {
    OwnerChannelSide.app => DirectionalKeys(send: appToPi, receive: piToApp),
    OwnerChannelSide.pi => DirectionalKeys(send: piToApp, receive: appToPi),
  };
}

/// Build the exact Owner-signed app handshake transcript.
Uint8List buildAppOwnerChannelTranscript({
  required String token,
  required List<int> appDhPublicKey,
  required List<int> piEdPublicKey,
}) {
  _requireLength(appDhPublicKey, _keyLength, 'app DH public key');
  _requireLength(piEdPublicKey, _keyLength, 'Pi Ed25519 public key');
  return _concat([
    utf8.encode('$ownerChannelSuite\napp\n'),
    utf8.encode(token),
    appDhPublicKey,
    piEdPublicKey,
  ]);
}

/// Build the exact Pi-signed handshake response transcript.
Uint8List buildPiOwnerChannelTranscript({
  required String token,
  required List<int> appDhPublicKey,
  required List<int> piDhPublicKey,
  required List<int> ownerEdPublicKey,
}) {
  _requireLength(appDhPublicKey, _keyLength, 'app DH public key');
  _requireLength(piDhPublicKey, _keyLength, 'Pi DH public key');
  _requireLength(ownerEdPublicKey, _keyLength, 'Owner Ed25519 public key');
  return _concat([
    utf8.encode('$ownerChannelSuite\npi\n'),
    utf8.encode(token),
    appDhPublicKey,
    piDhPublicKey,
    ownerEdPublicKey,
  ]);
}

/// Seal JSON as `version || seqLE64 || nonce || ciphertext || Poly1305 tag`.
///
/// The transmitted sequence is also authenticated as AEAD AAD. [nonce] is
/// test-only deterministic input; production callers omit it for a random
/// 192-bit nonce.
Future<Uint8List> sealOwnerChannelFrame({
  required List<int> key,
  required int sequence,
  required String json,
  List<int>? nonce,
}) async {
  _requireLength(key, _keyLength, 'owner-channel key');
  _requireUint64(sequence, 'sequence');
  if (nonce != null) _requireLength(nonce, _nonceLength, 'XChaCha20 nonce');
  final sequenceBytes = _sequenceLe64(sequence);
  final box = await _cipher.encrypt(
    utf8.encode(json),
    secretKey: SecretKey(key),
    nonce: nonce,
    aad: sequenceBytes,
  );
  return _concat([
    const [_frameVersion],
    sequenceBytes,
    box.nonce,
    box.cipherText,
    box.mac.bytes,
  ]);
}

/// Open a protected frame, returning null for all attacker-controlled faults.
///
/// Rejects a transmitted sequence at or below [lastSequence] before AEAD work,
/// then authenticates the same little-endian bytes as associated data.
Future<OpenedOwnerFrame?> openOwnerChannelFrame({
  required List<int> key,
  required List<int> frame,
  required int lastSequence,
}) async {
  try {
    _requireLength(key, _keyLength, 'owner-channel key');
    _requireUint64(lastSequence, 'lastSequence');
    if (frame.length < 1 + 8 + _nonceLength + _macLength ||
        frame.first != _frameVersion) {
      return null;
    }
    final sequenceBytes = Uint8List.fromList(frame.sublist(1, 9));
    final sequence = ByteData.sublistView(
      sequenceBytes,
    ).getUint64(0, Endian.little);
    if (sequence <= lastSequence || sequence > _maxSequence) return null;
    final body = Uint8List.fromList(frame.sublist(9));
    final box = SecretBox.fromConcatenation(
      body,
      nonceLength: _nonceLength,
      macLength: _macLength,
      copy: false,
    );
    final clear = await _cipher.decrypt(
      box,
      secretKey: SecretKey(key),
      aad: sequenceBytes,
    );
    return OpenedOwnerFrame(
      sequence: sequence,
      json: utf8.decode(clear, allowMalformed: false),
    );
  } on Object {
    return null;
  }
}

Future<Uint8List> _deriveDirection(
  List<int> sharedSecret,
  List<int> tokenBytes,
  String info,
) async {
  final key = await _hkdf.deriveKey(
    secretKey: SecretKey(sharedSecret),
    nonce: tokenBytes,
    info: utf8.encode(info),
  );
  return Uint8List.fromList(await key.extractBytes());
}

Uint8List _sequenceLe64(int sequence) {
  final bytes = Uint8List(8);
  ByteData.sublistView(bytes).setUint64(0, sequence, Endian.little);
  return bytes;
}

Uint8List _concat(List<List<int>> parts) {
  final output = Uint8List(
    parts.fold<int>(0, (length, part) => length + part.length),
  );
  var offset = 0;
  for (final part in parts) {
    output.setAll(offset, part);
    offset += part.length;
  }
  return output;
}

void _requireLength(List<int> bytes, int expected, String name) {
  if (bytes.length != expected) {
    throw ArgumentError('$name must be $expected bytes');
  }
}

void _requireUint64(int value, String name) {
  if (value < 0 || value > _maxSequence) {
    throw RangeError.range(value, 0, _maxSequence, name);
  }
}

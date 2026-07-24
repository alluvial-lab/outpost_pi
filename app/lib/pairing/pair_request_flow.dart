// PairRequest flow — signed ephemeral X25519 handshake over the pre-key link.
//
// Pairing frames remain plaintext, but each DH share is bound to the QR token
// and long-term Owner/Pi identities. Post-pair traffic uses the derived keys.

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/data/transport/secure_channel.dart';
import 'package:app/protocol/protocol.dart' show PairOk, PairRequest;
import 'package:app/protocol/uuid7.dart';
import 'package:cryptography/cryptography.dart';

import 'qr_scanner.dart';
import 'storage.dart';

// ---------------------------------------------------------------------------
// PeerTransport — minimal byte-level interface (was NoiseTransport pre-rollback)
// ---------------------------------------------------------------------------

/// Exchange raw inner-pairing bytes over a connected peer transport.
///
/// The pairing flow owns [close] after it finishes or fails; implementations do
/// not interpret the plaintext protocol payload.
abstract class PeerTransport {
  /// Send one complete pairing frame to the addressed Pi room.
  Future<void> send(Uint8List data);

  /// Receive the next complete pairing frame from the Pi.
  Future<Uint8List> receive();

  /// Release the pairing transport and any underlying socket resources.
  Future<void> close();
}

/// Report transport closure independently of its ordered data receive path.
///
/// Secure channels use this optional capability to trigger reconnect while a
/// previously received frame is blocked on durable sequence persistence.
abstract interface class PeerTransportCloseSignal {
  /// Complete when the underlying transport can no longer carry frames.
  Future<void> get transportClosed;
}

// ---------------------------------------------------------------------------
// PairingError
// ---------------------------------------------------------------------------

/// Report a typed pairing failure that callers can map to recovery UI.
class PairingError implements Exception {
  final String code;
  final String message;
  const PairingError({required this.code, required this.message});

  @override
  String toString() => 'PairingError($code): $message';
}

// ---------------------------------------------------------------------------
// PairingResult — output of [performPairing]
// ---------------------------------------------------------------------------

/// Wraps the persisted [PeerRecord] plus side hints the post-pair UI
/// (nickname modal) needs but that don't belong on the PeerRecord
/// itself. Plan/27 Wave A added [hostnameHint] so the modal can
/// pre-fill "Mac do Jacob" instead of the generic "Pi"; legacy Pis
/// that don't emit `hostname` leave it null and the modal falls back
/// to `peer.sessionName`.
class PairingResult {
  final PeerRecord peer;
  final String? hostnameHint;
  const PairingResult({required this.peer, this.hostnameHint});
}

// ---------------------------------------------------------------------------
// performPairing
// ---------------------------------------------------------------------------

/// Perform the signed ephemeral-DH pairing exchange and persist its peer record.
///
/// Rejects a relay mismatch or invalid Pi signature before persistence. The
/// caller retains transport-close ownership to coordinate channel adoption.
Future<PairingResult> performPairing({
  required QrPairPayload qr,
  required PeerTransport transport,
  required PairingStorage storage,
  SimpleKeyPair? ownerKey,
  required String deviceName,

  /// Effective relay URL the app is currently connected to. Used to
  /// detect mismatch vs `qr.relayUrl` for legacy QRs. Passed in by
  /// the caller (PairingViewModel reads it from Preferences).
  required String currentRelayUrl,
}) async {
  // Plan 14: legacy QRs may carry `r=<url>`. If that URL does not
  // match the app's configured relay, the device would attempt to
  // pair on the WRONG relay (or, after we centralised the connect
  // factory on resolveRelayUrl, would silently pair against the
  // user's relay while the Pi is waiting on another). Detect and
  // surface — UI (PairingViewModel) can show "trocar relay?" modal.
  if (qr.relayUrl != null &&
      toWsRelayUrl(qr.relayUrl!) != toWsRelayUrl(currentRelayUrl)) {
    throw PairingError(
      code: 'relay_mismatch',
      message:
          'QR points to "${qr.relayUrl}", '
          'but the app is configured for "$currentRelayUrl". '
          'Update the relay in settings or ask the Pi to generate '
          'a new QR.',
    );
  }

  // Plan 17 fix — set the outer envelope's `room` BEFORE sending
  // pair_request. Without this the relay would route to
  // (peer=Pi, room='main') which usually doesn't exist (Pi-ext is in
  // room=<hashOfCwd>) and drop with "dest not found". For legacy QRs
  // that don't carry `rm`, falls back to 'main' — the new
  // ConnectionManager discovery flow patches it up afterwards.
  final pairingRoomId = qr.roomId ?? 'main';
  if (transport case IActiveRoomTarget target) {
    target.setActiveRoom(pairingRoomId);
  }

  if (ownerKey == null) {
    throw const PairingError(
      code: 'owner_key_required',
      message: 'Owner identity is required for secure pairing',
    );
  }

  final dh = await generateOwnerChannelKeyPair();
  try {
    final piEdPublicKey = Uint8List.fromList(qr.epkBytes);
    final ownerPublicKey = await ownerKey.extractPublicKey();
    final appTranscript = buildAppOwnerChannelTranscript(
      token: qr.token,
      appDhPublicKey: dh.publicKey,
      piEdPublicKey: piEdPublicKey,
    );
    final appSignature = await Ed25519().sign(appTranscript, keyPair: ownerKey);
    final pairProof = await buildOwnerChannelPairProof(
      token: qr.token,
      ownerEdPublicKey: ownerPublicKey.bytes,
      appDhPublicKey: dh.publicKey,
      piEdPublicKey: piEdPublicKey,
    );
    final id = uuid7();
    final request = PairRequest(
      id: id,
      tokenId: base64.encode(pairProof.tokenId),
      pairMac: base64.encode(pairProof.mac),
      deviceName: deviceName,
      dhPk: base64.encode(dh.publicKey),
      dhSig: base64.encode(appSignature.bytes),
    );
    await transport.send(
      Uint8List.fromList(utf8.encode(jsonEncode(request.toJson()))),
    );

    final raw = await transport.receive();
    final inner = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    final type = inner['type'] as String?;

    if (type == 'pair_ok' && inner['in_reply_to'] == id) {
      final pairOk = PairOk.fromJson(inner);
      final piDhPublicKey = _decodeFixedBase64(pairOk.dhPk, 32);
      final piDhSignature = _decodeFixedBase64(pairOk.dhSig, 64);
      if (piDhPublicKey == null || piDhSignature == null) {
        throw const PairingError(
          code: 'bad_dh_sig',
          message: 'Pi returned an invalid secure-channel handshake',
        );
      }
      final piTranscript = buildPiOwnerChannelTranscript(
        token: qr.token,
        appDhPublicKey: dh.publicKey,
        piDhPublicKey: piDhPublicKey,
        ownerEdPublicKey: ownerPublicKey.bytes,
      );
      final verified = await Ed25519().verify(
        piTranscript,
        signature: Signature(
          piDhSignature,
          publicKey: SimplePublicKey(piEdPublicKey, type: KeyPairType.ed25519),
        ),
      );
      if (!verified) {
        throw const PairingError(
          code: 'bad_dh_sig',
          message: 'Pi secure-channel signature verification failed',
        );
      }

      final shared = await deriveOwnerChannelSharedSecret(
        dh.secretKey,
        piDhPublicKey,
      );
      final keys = await deriveOwnerChannelKeys(
        sharedSecret: shared,
        token: qr.token,
        side: OwnerChannelSide.app,
      );
      final rawRoom = inner['room_id'];
      final piEchoedRoom = rawRoom is String && rawRoom.isNotEmpty;
      final piRoomId = piEchoedRoom ? pairOk.roomId : (qr.roomId ?? 'main');
      final peer = PeerRecord(
        remoteEpk: qr.epk,
        sessionName: pairOk.sessionName,
        relayUrl: qr.relayUrl ?? currentRelayUrl,
        pairedAt: DateTime.now().toUtc().toIso8601String(),
        roomId: piRoomId,
        harness: pairOk.harness,
        channel: OwnerChannelState(
          sendKey: base64.encode(keys.send),
          receiveKey: base64.encode(keys.receive),
        ),
      );
      await storage.savePairedPeer(peer);
      return PairingResult(peer: peer, hostnameHint: pairOk.hostname);
    }

    if (type == 'pair_error') {
      throw PairingError(
        code: inner['code'] as String,
        message: inner['message'] as String? ?? '',
      );
    }

    throw PairingError(
      code: 'unexpected_response',
      message: 'Unknown response type: $type',
    );
  } finally {
    dh.secretKey.fillRange(0, dh.secretKey.length, 0);
  }
}

Uint8List? _decodeFixedBase64(String? encoded, int length) {
  if (encoded == null) return null;
  try {
    final bytes = base64.decode(encoded);
    return bytes.length == length ? Uint8List.fromList(bytes) : null;
  } on FormatException {
    return null;
  }
}

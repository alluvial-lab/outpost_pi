import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/secure_channel.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/qr_scanner.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

class _Q {
  final _buffer = <Uint8List>[];
  final _waiters = <Completer<Uint8List>>[];

  void add(Uint8List data) {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(data);
    } else {
      _buffer.add(data);
    }
  }

  Future<Uint8List> next() {
    if (_buffer.isNotEmpty) return Future.value(_buffer.removeAt(0));
    final completer = Completer<Uint8List>();
    _waiters.add(completer);
    return completer.future;
  }
}

class _MemTransport implements PeerTransport {
  _MemTransport({required _Q send, required _Q receive})
    : _send = send,
      _receive = receive;

  final _Q _send;
  final _Q _receive;

  @override
  Future<void> send(Uint8List data) async => _send.add(data);

  @override
  Future<Uint8List> receive() => _receive.next();

  @override
  Future<void> close() async {}
}

class _RoomAwareMemTransport extends _MemTransport
    implements IActiveRoomTarget {
  _RoomAwareMemTransport({required super.send, required super.receive});

  final List<String> activeRooms = <String>[];

  @override
  void setActiveRoom(String roomId) => activeRooms.add(roomId);
}

class _FakeStorage extends PairingStorage {
  final List<PeerRecord> saved = <PeerRecord>[];

  @override
  Future<List<PeerRecord>> listPeers() async => saved;

  @override
  Future<void> savePairedPeer(PeerRecord record) async => saved.add(record);
}

const _token = 'AAAAAAAAAAAAAAAAAAAAAA';
late SimpleKeyPair _ownerKey;
late SimpleKeyPair _piKey;
late String _piEpk;

QrPairPayload _qr({String? relayUrl, String? roomId}) => QrPairPayload(
  token: _token,
  epk: _piEpk,
  sessionName: 'Pi',
  relayUrl: relayUrl,
  roomId: roomId,
);

Future<void> _replyPairOk(
  PeerTransport pi, {
  Map<String, dynamic> fields = const <String, dynamic>{},
  bool forgedSignature = false,
  bool omitDh = false,
  List<int>? piDhPublicKey,
  void Function(PairRequest request)? observeRequest,
  void Function(Map<String, dynamic> request)? observeRequestJson,
}) async {
  final raw = await pi.receive();
  final requestJson = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
  final request = PairRequest.fromJson(requestJson);
  observeRequest?.call(request);
  observeRequestJson?.call(requestJson);
  final appDhPublic = Uint8List.fromList(base64.decode(request.dhPk!));
  final appSignature = Uint8List.fromList(base64.decode(request.dhSig!));
  final ownerPublic = await _ownerKey.extractPublicKey();
  final piPublic = await _piKey.extractPublicKey();
  final proof = await buildOwnerChannelPairProof(
    token: _token,
    ownerEdPublicKey: ownerPublic.bytes,
    appDhPublicKey: appDhPublic,
    piEdPublicKey: piPublic.bytes,
  );
  expect(request.tokenId, base64.encode(proof.tokenId));
  expect(request.pairMac, base64.encode(proof.mac));
  final appTranscript = buildAppOwnerChannelTranscript(
    token: _token,
    appDhPublicKey: appDhPublic,
    piEdPublicKey: piPublic.bytes,
  );
  expect(
    await Ed25519().verify(
      appTranscript,
      signature: Signature(appSignature, publicKey: ownerPublic),
    ),
    isTrue,
  );

  final response = <String, dynamic>{
    'type': 'pair_ok',
    'in_reply_to': request.id,
    'session_name': 'Pi',
    ...fields,
  };
  if (!omitDh) {
    final piDh =
        piDhPublicKey ?? (await generateOwnerChannelKeyPair()).publicKey;
    final transcript = buildPiOwnerChannelTranscript(
      token: _token,
      appDhPublicKey: appDhPublic,
      piDhPublicKey: piDh,
      ownerEdPublicKey: ownerPublic.bytes,
    );
    final signer = forgedSignature ? await Ed25519().newKeyPair() : _piKey;
    final signature = await Ed25519().sign(transcript, keyPair: signer);
    response['dh_pk'] = base64.encode(piDh);
    response['dh_sig'] = base64.encode(signature.bytes);
  }
  await pi.send(Uint8List.fromList(utf8.encode(jsonEncode(response))));
}

Future<PairingResult> _perform({
  required QrPairPayload qr,
  required PeerTransport transport,
  required PairingStorage storage,
  String currentRelayUrl = 'wss://relay.example',
}) => performPairing(
  qr: qr,
  transport: transport,
  storage: storage,
  ownerKey: _ownerKey,
  deviceName: 'phone',
  currentRelayUrl: currentRelayUrl,
);

void main() {
  setUpAll(() async {
    _ownerKey = await Ed25519().newKeyPair();
    _piKey = await Ed25519().newKeyPair();
    final piPublic = await _piKey.extractPublicKey();
    _piEpk = base64Url.encode(piPublic.bytes).replaceAll('=', '');
  });

  test('channel traffic racing pair_ok is skipped, pairing completes', () async {
    final appToPi = _Q();
    final piToApp = _Q();
    final pi = _MemTransport(send: piToApp, receive: appToPi);
    final app = _MemTransport(send: appToPi, receive: piToApp);
    final storage = _FakeStorage();
    unawaited(() async {
      // Sealed-looking ciphertext (invalid UTF-8 — the live failure was
      // FormatException: Unexpected extension byte (at offset 1)), then a
      // JSON frame replying to a different id, then the real pair_ok.
      await pi.send(Uint8List.fromList([0x80, 0xBF, 0x00, 0xFE]));
      await pi.send(
        Uint8List.fromList(
          utf8.encode(jsonEncode({'type': 'agent_chunk', 'in_reply_to': 'other'})),
        ),
      );
      await _replyPairOk(pi, fields: const {'session_name': 'race session'});
    }());

    final result = await _perform(qr: _qr(), transport: app, storage: storage);

    expect(result.peer.sessionName, 'race session');
    expect(result.peer.channel, isNotNull);
    expect(storage.saved, [result.peer]);
  });

  test('garbage frame before pair_error still surfaces the error code', () async {
    final appToPi = _Q();
    final piToApp = _Q();
    final pi = _MemTransport(send: piToApp, receive: appToPi);
    final app = _MemTransport(send: appToPi, receive: piToApp);
    final storage = _FakeStorage();
    unawaited(() async {
      // Wait for the request to arrive so our frames are ordered after it
      // and the error replies to the right id.
      final raw = await pi.receive();
      final requestId =
          (jsonDecode(utf8.decode(raw)) as Map<String, dynamic>)['id'];
      await pi.send(Uint8List.fromList([0x80, 0xBF]));
      await pi.send(
        Uint8List.fromList(
          utf8.encode(jsonEncode({
            'type': 'pair_error',
            'in_reply_to': requestId,
            'code': 'token_unknown',
            'message': 'nope',
          })),
        ),
      );
    }());

    await expectLater(
      _perform(qr: _qr(), transport: app, storage: storage),
      throwsA(isA<PairingError>().having((e) => e.code, 'code', 'token_unknown')),
    );
    expect(storage.saved, isEmpty);
  });

  test('relay mismatch aborts before sending or persisting', () async {
    final storage = _FakeStorage();
    final transport = _MemTransport(send: _Q(), receive: _Q());
    await expectLater(
      _perform(
        qr: _qr(relayUrl: 'wss://other.example'),
        transport: transport,
        storage: storage,
        currentRelayUrl: 'wss://mine.example',
      ),
      throwsA(
        isA<PairingError>().having(
          (error) => error.code,
          'code',
          'relay_mismatch',
        ),
      ),
    );
    expect(storage.saved, isEmpty);
  });

  test(
    'generated pair_request is signed and success persists channel keys',
    () async {
      final appToPi = _Q();
      final piToApp = _Q();
      final pi = _MemTransport(send: piToApp, receive: appToPi);
      final app = _MemTransport(send: appToPi, receive: piToApp);
      final storage = _FakeStorage();
      PairRequest? observed;
      Map<String, dynamic>? observedJson;
      unawaited(
        _replyPairOk(
          pi,
          fields: const <String, dynamic>{
            'session_name': 'test session',
            'room_id': 'room-from-pi',
          },
          observeRequest: (request) => observed = request,
          observeRequestJson: (request) => observedJson = request,
        ),
      );

      final result = await _perform(
        qr: _qr(roomId: 'room-from-qr'),
        transport: app,
        storage: storage,
      );

      expect(observed, isNotNull);
      expect(observed!.tokenId, isNotNull);
      expect(observed!.pairMac, isNotNull);
      expect(observed!.dhPk, isNotNull);
      expect(observed!.dhSig, isNotNull);
      expect(observedJson, isNot(contains('token')));
      expect(jsonEncode(observedJson), isNot(contains(_token)));
      expect(result.peer.roomId, 'room-from-pi');
      expect(result.peer.channel, isNotNull);
      expect(result.peer.channel!.sendSequence, 0);
      expect(result.peer.channel!.receiveSequence, 0);
      expect(base64.decode(result.peer.channel!.sendKey), hasLength(32));
      expect(storage.saved, [result.peer]);
    },
  );

  test('pair_ok without room_id falls back to QR room', () async {
    final appToPi = _Q();
    final piToApp = _Q();
    final pi = _MemTransport(send: piToApp, receive: appToPi);
    final app = _RoomAwareMemTransport(send: appToPi, receive: piToApp);
    unawaited(_replyPairOk(pi));

    final result = await _perform(
      qr: _qr(roomId: 'room-from-qr'),
      transport: app,
      storage: _FakeStorage(),
    );

    expect(app.activeRooms, ['room-from-qr']);
    expect(result.peer.roomId, 'room-from-qr');
  });

  test('forged Pi DH signature aborts and persists nothing', () async {
    final appToPi = _Q();
    final piToApp = _Q();
    final pi = _MemTransport(send: piToApp, receive: appToPi);
    final app = _MemTransport(send: appToPi, receive: piToApp);
    final storage = _FakeStorage();
    unawaited(_replyPairOk(pi, forgedSignature: true));

    await expectLater(
      _perform(qr: _qr(), transport: app, storage: storage),
      throwsA(
        isA<PairingError>().having((error) => error.code, 'code', 'bad_dh_sig'),
      ),
    );
    expect(storage.saved, isEmpty);
  });

  test('low-order Pi DH share aborts and persists nothing', () async {
    final appToPi = _Q();
    final piToApp = _Q();
    final pi = _MemTransport(send: piToApp, receive: appToPi);
    final app = _MemTransport(send: appToPi, receive: piToApp);
    final storage = _FakeStorage();
    unawaited(_replyPairOk(pi, piDhPublicKey: Uint8List(32)));

    await expectLater(
      _perform(qr: _qr(), transport: app, storage: storage),
      throwsA(anything),
    );
    expect(storage.saved, isEmpty);
  });

  test('missing Pi DH fields aborts and persists nothing', () async {
    final appToPi = _Q();
    final piToApp = _Q();
    final pi = _MemTransport(send: piToApp, receive: appToPi);
    final app = _MemTransport(send: appToPi, receive: piToApp);
    final storage = _FakeStorage();
    unawaited(_replyPairOk(pi, omitDh: true));

    await expectLater(
      _perform(qr: _qr(), transport: app, storage: storage),
      throwsA(
        isA<PairingError>().having((error) => error.code, 'code', 'bad_dh_sig'),
      ),
    );
    expect(storage.saved, isEmpty);
  });

  test('pair_error remains a typed failure without persistence', () async {
    final appToPi = _Q();
    final piToApp = _Q();
    final pi = _MemTransport(send: piToApp, receive: appToPi);
    final app = _MemTransport(send: appToPi, receive: piToApp);
    final storage = _FakeStorage();
    unawaited(() async {
      final raw = await pi.receive();
      final request = PairRequest.fromJson(
        jsonDecode(utf8.decode(raw)) as Map<String, dynamic>,
      );
      await pi.send(
        Uint8List.fromList(
          utf8.encode(
            jsonEncode(<String, dynamic>{
              'type': 'pair_error',
              'in_reply_to': request.id,
              'code': 'token_expired',
              'message': 'expired',
            }),
          ),
        ),
      );
    }());

    await expectLater(
      _perform(qr: _qr(), transport: app, storage: storage),
      throwsA(
        isA<PairingError>().having(
          (error) => error.code,
          'code',
          'token_expired',
        ),
      ),
    );
    expect(storage.saved, isEmpty);
  });
}

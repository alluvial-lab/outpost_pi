import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/qr_scanner.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/protocol/uuid7.dart';
import 'package:cryptography/cryptography.dart';

import 'eventually.dart';
import 'harness_endpoints.dart';
import 'pi_host_client.dart';
import 'raw_owner_relay_client.dart';

final class PairCodeObservation {
  const PairCodeObservation({
    required this.qr,
    required this.uri,
    required this.expiresAt,
  });

  final QrPairPayload qr;
  final String uri;
  final DateTime expiresAt;
}

/// Read a production-generated pair code through the headless E2E file seam.
///
/// The real extension still issues the bearer token; the harness only exposes
/// that file to the test process and never fabricates pairing material.
Future<PairCodeObservation> waitForPairCode(
  PiHostClient host, {
  String args = 'pair',
}) async {
  await host.invokeOutpostPi(args);
  final observation = await eventually<PairCodeObservation>(
    () async {
      final payload = await host.pairCode();
      final uri = payload['uri'];
      final token = payload['token'];
      final expiresAt = payload['expiresAt'];
      if (uri is! String || token is! String || expiresAt is! num) return null;
      final qr = QrPairPayload.tryParse(uri);
      if (qr == null || qr.token != token) return null;
      return PairCodeObservation(
        qr: qr,
        uri: uri,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt.toInt()),
      );
    },
    timeout: const Duration(seconds: 10),
    description: 'pair-code file publication',
  );
  // The extension refuses to overwrite a pre-existing pair-code file
  // (assertPairCodeTargetAbsent); consume the seam so a later `pair`
  // command in the same host generation can publish a fresh code.
  await host.consumePairCode();
  return observation;
}

/// Own one real app transport from relay auth through pairing and hydration.
final class PairingStack {
  PairingStack._({
    required this.endpoints,
    required this.qr,
    required this.storage,
    required this.ownerKey,
    required _RecordingPeerTransport transport,
    required String deviceId,
  }) : _transport = transport,
       _deviceId = deviceId;

  static Future<PairingStack> connect({
    required HarnessEndpoints endpoints,
    required QrPairPayload qr,
    required PairingStorage storage,
    SimpleKeyPair? ownerKey,
  }) async {
    ownerKey ??= await Ed25519().newKeyPair();
    final deviceId = 'pairing-e2e-${DateTime.now().microsecondsSinceEpoch}';
    final ws = await WsTransport.connect(
      relayUrl: endpoints.relay.toString(),
      peerPubkey: qr.epk,
      ed25519Key: ownerKey,
      deviceId: deviceId,
      activeRoom: qr.roomId ?? 'main',
    ).timeout(const Duration(seconds: 10));
    return PairingStack._(
      endpoints: endpoints,
      qr: qr,
      storage: storage,
      ownerKey: ownerKey,
      transport: _RecordingPeerTransport(ws),
      deviceId: deviceId,
    );
  }

  final HarnessEndpoints endpoints;
  final QrPairPayload qr;
  final PairingStorage storage;
  final SimpleKeyPair ownerKey;
  final _RecordingPeerTransport _transport;
  final String _deviceId;
  final List<Uint8List> _protectedOutboundFrames = <Uint8List>[];
  bool _transferred = false;
  bool _closed = false;

  Future<PairingResult> pair({
    required String deviceName,
    Future<void> Function(Map<String, dynamic> request)? beforeRequestSend,
  }) async {
    if (beforeRequestSend != null) {
      _transport.beforeNextSend = (bytes) => beforeRequestSend(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
    }
    try {
      final result = await performPairing(
        qr: qr,
        transport: _transport,
        storage: storage,
        ownerKey: ownerKey,
        deviceName: deviceName,
        currentRelayUrl: endpoints.relay.toString(),
      ).timeout(const Duration(seconds: 10));
      _transport.clearSentFrames();
      return result;
    } finally {
      _transport.beforeNextSend = null;
    }
  }

  /// Exchange one deliberately hand-built pre-key frame with the Pi.
  Future<Map<String, dynamic>> exchangePairingJson(
    Map<String, dynamic> message,
  ) async {
    await _transport.send(Uint8List.fromList(utf8.encode(jsonEncode(message))));
    final response = await _transport.receive();
    return jsonDecode(utf8.decode(response)) as Map<String, dynamic>;
  }

  Future<RawOwnerRelayClient> openRawOwnerRelayClient() =>
      RawOwnerRelayClient.connect(
        relay: endpoints.relay,
        ownerKey: ownerKey,
        deviceId: '$_deviceId-raw-${DateTime.now().microsecondsSinceEpoch}',
      );

  Future<HydratedSession> adoptAndHydrate(PairingResult result) async {
    if (_transferred) {
      throw StateError('transport ownership already transferred');
    }
    _transferred = true;
    final channel = SecurePeerChannel(
      transport: _transport,
      storage: storage,
      peer: result.peer,
    );
    final connection = ConnectionManager(
      factory: (peer, cancel) async {
        final current = await storage.loadPeer(peer.remoteEpk);
        if (current?.channel == null) {
          throw StateError('e2e reconnect lost owner-channel state');
        }
        final ws = await WsTransport.connect(
          relayUrl: endpoints.relay.toString(),
          peerPubkey: current!.remoteEpk,
          ed25519Key: ownerKey,
          deviceId: _deviceId,
          activeRoom: current.roomId ?? 'main',
          cancellation: cancel,
        ).timeout(const Duration(seconds: 10));
        if (cancel.isCancelled) {
          await ws.close();
          throw StateError('e2e reconnect was cancelled');
        }
        final recording = _RecordingPeerTransport(
          ws,
          sink: _protectedOutboundFrames,
        );
        return SecurePeerChannel(
          transport: recording,
          storage: storage,
          peer: current,
        );
      },
      storage: storage,
      emitDebounce: Duration.zero,
    );
    final sync = SyncService(connection, LocalBoxes());
    _transport.copySentFramesTo(_protectedOutboundFrames);
    _transport.setSink(_protectedOutboundFrames);
    connection.adopt(channel, result.peer);
    connection.subscribeToPeers(<String>[result.peer.remoteEpk]);
    final sessionId = await eventually<String>(
      () async => connection.activeSessionId,
      timeout: const Duration(seconds: 10),
      description: 'canonical room session identity',
    );
    await sync.activate(result.peer.remoteEpk, result.peer.roomId ?? 'main');
    return HydratedSession(
      peer: result.peer,
      sessionId: sessionId,
      initialChannel: channel,
      connection: connection,
      sync: sync,
      storage: storage,
      protectedOutboundFrames: _protectedOutboundFrames,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_transferred) await _transport.close();
  }
}

final class HydratedSession {
  const HydratedSession({
    required this.peer,
    required this.sessionId,
    required this.initialChannel,
    required this.connection,
    required this.sync,
    required this.storage,
    required this.protectedOutboundFrames,
  });

  final PeerRecord peer;
  final String sessionId;
  final SecurePeerChannel initialChannel;
  final ConnectionManager connection;
  final SyncService sync;
  final PairingStorage storage;
  final List<Uint8List> protectedOutboundFrames;

  IChannel get currentChannel {
    final value = connection.channel;
    if (value == null) throw StateError('owner channel is not online');
    return value;
  }

  /// Send a protected protocol ping and wait for its protected pong.
  Future<void> ping() async {
    final id = uuid7();
    final pong = currentChannel.serverMessages.firstWhere(
      (message) => message is Pong && message.inReplyTo == id,
    );
    await currentChannel.send(Ping(id: id));
    await pong.timeout(const Duration(seconds: 10));
  }

  Future<OwnerChannelState> persistedChannelState() async {
    final current = await storage.loadPeer(peer.remoteEpk);
    final channel = current?.channel;
    if (channel == null) throw StateError('owner channel was not persisted');
    return channel;
  }

  Future<void> close() async {
    sync.dispose();
    await connection.disconnect();
    connection.dispose();
  }
}

final class _RecordingPeerTransport
    implements PeerTransport, IControlLink, IActiveRoomTarget {
  _RecordingPeerTransport(this._delegate, {List<Uint8List>? sink})
    : _sink = sink;

  final WsTransport _delegate;
  final List<Uint8List> _frames = <Uint8List>[];
  List<Uint8List>? _sink;
  Future<void> Function(Uint8List bytes)? beforeNextSend;

  void clearSentFrames() => _frames.clear();

  void setSink(List<Uint8List> sink) => _sink = sink;

  void copySentFramesTo(List<Uint8List> sink) => sink.addAll(_frames);

  @override
  Future<void> send(Uint8List data) async {
    final copy = Uint8List.fromList(data);
    final beforeSend = beforeNextSend;
    beforeNextSend = null;
    if (beforeSend != null) await beforeSend(copy);
    _frames.add(copy);
    _sink?.add(copy);
    await _delegate.send(data);
  }

  @override
  Future<Uint8List> receive() => _delegate.receive();

  @override
  Future<void> close() => _delegate.close();

  @override
  Stream<ControlInbound> get controlFrames => _delegate.controlFrames;

  @override
  void sendControl(Map<String, dynamic> json) => _delegate.sendControl(json);

  @override
  void setActiveRoom(String roomId) => _delegate.setActiveRoom(roomId);
}

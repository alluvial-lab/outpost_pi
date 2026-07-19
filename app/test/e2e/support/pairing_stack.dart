import 'dart:async';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/qr_scanner.dart';
import 'package:app/pairing/storage.dart';
import 'package:cryptography/cryptography.dart';

import 'eventually.dart';
import 'harness_endpoints.dart';
import 'pi_host_client.dart';

final class PairCodeObservation {
  const PairCodeObservation({required this.qr, required this.expiresAt});

  final QrPairPayload qr;
  final DateTime expiresAt;
}

/// Read a production pair-code only after it crossed the SDK TUI action boundary.
Future<PairCodeObservation> waitForPairCode(
  PiHostClient host, {
  String args = 'pair',
}) async {
  await host.invokeOutpostPi(args);
  return eventually<PairCodeObservation>(
    () async {
      final events = await host.eventsAfter(0);
      for (final event in events.reversed) {
        final payload = event.payload;
        if (event.kind != 'tui_message' ||
            payload is! Map<String, dynamic> ||
            payload['customType'] != 'outpost-pi:pair-code') {
          continue;
        }
        final details = payload['details'];
        if (details is! Map<String, dynamic>) continue;
        final uri = details['uri'];
        final expiresAt = details['expiresAt'];
        if (uri is! String || expiresAt is! num) continue;
        final qr = QrPairPayload.tryParse(uri);
        if (qr == null) continue;
        return PairCodeObservation(
          qr: qr,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt.toInt()),
        );
      }
      return null;
    },
    timeout: const Duration(seconds: 10),
    description: 'pair-code publication',
  );
}

/// Own one real app transport from relay auth through pairing and hydration.
final class PairingStack {
  PairingStack._({
    required this.endpoints,
    required this.qr,
    required this.storage,
    required this.transport,
  });

  static Future<PairingStack> connect({
    required HarnessEndpoints endpoints,
    required QrPairPayload qr,
    required PairingStorage storage,
  }) async {
    final ownerKey = await Ed25519().newKeyPair();
    final transport = await WsTransport.connect(
      relayUrl: endpoints.relay.toString(),
      peerPubkey: qr.epk,
      ed25519Key: ownerKey,
      deviceId: 'pairing-e2e-${DateTime.now().microsecondsSinceEpoch}',
      activeRoom: qr.roomId ?? 'main',
    ).timeout(const Duration(seconds: 10));
    return PairingStack._(
      endpoints: endpoints,
      qr: qr,
      storage: storage,
      transport: transport,
    );
  }

  final HarnessEndpoints endpoints;
  final QrPairPayload qr;
  final PairingStorage storage;
  final WsTransport transport;
  bool _transferred = false;
  bool _closed = false;

  Future<PairingResult> pair({required String deviceName}) => performPairing(
    qr: qr,
    transport: transport,
    storage: storage,
    deviceName: deviceName,
    currentRelayUrl: endpoints.relay.toString(),
  ).timeout(const Duration(seconds: 10));

  Future<HydratedSession> adoptAndHydrate(PairingResult result) async {
    if (_transferred) throw StateError('transport ownership already transferred');
    _transferred = true;
    final channel = PlainPeerChannel(transport: transport);
    final connection = ConnectionManager(
      factory: (_, _) => Future<IChannel>.error(
        StateError('e2e adopted channel must not invoke reconnect factory'),
      ),
      storage: storage,
      emitDebounce: Duration.zero,
    );
    final sync = SyncService(connection, LocalBoxes());
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
      channel: channel,
      connection: connection,
      sync: sync,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_transferred) await transport.close();
  }
}

final class HydratedSession {
  const HydratedSession({
    required this.peer,
    required this.sessionId,
    required this.channel,
    required this.connection,
    required this.sync,
  });

  final PeerRecord peer;
  final String sessionId;
  final PlainPeerChannel channel;
  final ConnectionManager connection;
  final SyncService sync;

  Future<void> close() async {
    sync.dispose();
    await connection.disconnect();
    connection.dispose();
  }
}

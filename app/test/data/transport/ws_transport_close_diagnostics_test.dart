import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/protocol/protocol.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'server close frame records code, bounded reason tag, and origin',
    () async {
      final relay = await _CloseRelay.start();
      addTearDown(relay.close);
      final transport = await _connect(relay);
      addTearDown(transport.close);

      await relay.closePeer(4001, 'relay_outbound_mailbox_saturated');
      await transport.transportClosed.timeout(const Duration(seconds: 1));

      expect(
        transport.closeDetails,
        const ChannelCloseDetails(
          origin: ChannelCloseOrigin.serverCloseFrame,
          closeCode: 4001,
          closeReason: 'present',
        ),
      );
    },
  );

  test(
    'server close reason is categorized without retaining free text',
    () async {
      final relay = await _CloseRelay.start();
      addTearDown(relay.close);
      final transport = await _connect(relay);
      addTearDown(transport.close);

      await relay.closePeer(4002, 'could contain payload text');
      await transport.transportClosed.timeout(const Duration(seconds: 1));

      expect(transport.closeDetails?.closeReason, 'present');
    },
  );

  test('local close records the exact initiating code path', () async {
    final relay = await _CloseRelay.start();
    addTearDown(relay.close);
    final transport = await _connect(relay);

    await transport.closeWithPath(ChannelLocalClosePath.hedgeLoser);

    expect(
      transport.closeDetails,
      const ChannelCloseDetails(
        origin: ChannelCloseOrigin.localClose,
        localPath: ChannelLocalClosePath.hedgeLoser,
      ),
    );
  });

  test('outbound diagnostics order frame intents before local Close', () async {
    final relay = await _CloseRelay.start();
    addTearDown(relay.close);
    final log = _RecordingDebugLog();
    final transport = await _connect(relay, debugLog: log);

    await transport.send(Uint8List(256));
    transport.sendControl(presenceCheckFrame(const []));
    await transport.closeWithPath(ChannelLocalClosePath.hedgeLoser);

    final events = log.events.whereType<WsOutEvent>().toList();
    expect(events.map((event) => event.stage), <WsOutboundStage>[
      WsOutboundStage.hello,
      WsOutboundStage.auth,
      WsOutboundStage.readinessProbe,
      WsOutboundStage.envelope,
      WsOutboundStage.control,
      WsOutboundStage.closeInitiated,
    ]);
    expect(events.map((event) => event.sequence), <int>[1, 2, 3, 4, 5, 6]);
    expect(events.map((event) => event.connectionId).toSet(), hasLength(1));
    expect(events.take(5).map((event) => event.firstByte), everyElement(0x81));
    expect(events.take(5).map((event) => event.masked), everyElement(isTrue));
    expect(events[3].lengthClass, WsPayloadLengthClass.extended16);
    expect(events.last.firstByte, 0x88);
    expect(events.last.payloadBytes, 0);
    expect(events.last.lengthClass, WsPayloadLengthClass.inline7);
    expect(events.last.closePath, ChannelLocalClosePath.hedgeLoser.name);
  });
}

final class _RecordingDebugLog implements DebugLog {
  final events = <DebugEvent>[];

  @override
  void log(DebugEvent event) => events.add(event);

  @override
  Future<String?> export() async => null;

  @override
  Future<void> clear() async {}

  @override
  void dispose() {}
}

Future<WsTransport> _connect(_CloseRelay relay, {DebugLog? debugLog}) async =>
    WsTransport.connect(
      relayUrl: relay.url,
      peerPubkey: 'cGVlcg==',
      ed25519Key: await Ed25519().newKeyPair(),
      deviceId: 'close-diagnostics-device',
      debugLog: debugLog,
    );

final class _CloseRelay {
  _CloseRelay._(this._server);

  final HttpServer _server;
  final Completer<WebSocket> _peer = Completer<WebSocket>();
  StreamSubscription<HttpRequest>? _requests;

  String get url => 'ws://${_server.address.host}:${_server.port}';

  static Future<_CloseRelay> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final relay = _CloseRelay._(server);
    relay._requests = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      if (!relay._peer.isCompleted) relay._peer.complete(socket);
      var handshakeStage = 0;
      socket.listen((raw) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        if (handshakeStage == 0 && frame['type'] == 'hello') {
          handshakeStage = 1;
          socket.add(
            jsonEncode({
              'type': 'challenge',
              'nonce': base64Encode(Uint8List(32)),
            }),
          );
          return;
        }
        if (handshakeStage == 1 && frame['type'] == 'auth') {
          handshakeStage = 2;
          socket.add(jsonEncode({'type': 'presence', 'states': <Object>[]}));
        }
      });
    });
    return relay;
  }

  Future<void> closePeer(int code, String reason) async {
    final socket = await _peer.future;
    await socket.close(code, reason);
  }

  Future<void> close() async {
    if (_peer.isCompleted) {
      final socket = await _peer.future;
      if (socket.readyState == WebSocket.open) await socket.close();
    }
    await _requests?.cancel();
    await _server.close(force: true);
  }
}

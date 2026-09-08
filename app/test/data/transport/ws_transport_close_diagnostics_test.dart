import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/protocol/protocol.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  test('FNV-1a64 hash uses the shared known vector', () {
    expect(_hashText('hello'), 'a430d84680aabd0b');
  });

  test(
    'server close frame records code, bounded reason tag, and origin',
    () async {
      final relay = await _CloseRelay.start();
      addTearDown(relay.close);
      final transport = await _connect(relay.url);
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
    'probe pins dart close code for an abrupt mid-frame socket death',
    () async {
      final relay = await _AbruptRelay.start();
      addTearDown(relay.close);
      final transport = await _connect(relay.url);
      addTearDown(transport.close);

      await relay.killMidFrame();
      await transport.transportClosed.timeout(const Duration(seconds: 1));

      // Dart 3.13.1 reports an incomplete frame followed by TCP death as
      // abnormalClosure (1006), with no server Close frame received. This
      // probe is intentionally kept against the pinned Flutter/Dart runtime
      // before attribution logic interprets the value.
      expect(
        transport.closeDetails?.closeCode,
        WebSocketStatus.abnormalClosure,
      );
    },
  );

  test('probe pins dart close code when its ping receives no pong', () async {
    final relay = await _AbruptRelay.start();
    addTearDown(relay.close);
    final channel = IOWebSocketChannel.connect(
      relay.url,
      pingInterval: const Duration(milliseconds: 50),
    );
    addTearDown(() async {
      try {
        await channel.sink.close();
      } on Object {
        // The missed-pong watchdog may have already closed the channel.
      }
    });
    final done = Completer<void>();
    channel.stream.listen(
      (_) {},
      onError: (_, _) {},
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );

    await channel.ready;
    await relay.connected;
    await done.future.timeout(const Duration(seconds: 2));

    // IOWebSocketChannel delegates to dart:io, whose missed-pong watchdog
    // closes with goingAway (1001), not protocolError (1002).
    expect(channel.closeCode, WebSocketStatus.goingAway);
  });

  test(
    'probe pins dart close code for post-handshake framing garbage',
    () async {
      final relay = await _AbruptRelay.start();
      addTearDown(relay.close);
      final channel = IOWebSocketChannel.connect(relay.url);
      addTearDown(() async {
        try {
          await channel.sink.close();
        } on Object {
          // The protocol-error path may have already closed the channel.
        }
      });
      final done = Completer<void>();
      channel.stream.listen(
        (_) {},
        onError: (_, _) {},
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );

      await channel.ready;
      await relay.connected;
      await relay.sendFramingGarbage();
      await done.future.timeout(const Duration(seconds: 2));

      expect(channel.closeCode, WebSocketStatus.protocolError);
    },
  );

  test(
    'inbound rows carry per-message hash and loss exposes running hash',
    () async {
      final relay = await _CloseRelay.start();
      addTearDown(relay.close);
      final log = _RecordingDebugLog();
      final transport = await _connect(relay.url, debugLog: log);
      addTearDown(transport.close);

      await relay.closePeer(4001, 'relay_outbound_mailbox_saturated');
      await transport.transportClosed.timeout(const Duration(seconds: 1));

      final events = log.events.whereType<WsInEvent>().toList();
      expect(events, hasLength(2));
      expect(events.map((event) => event.idx), <int?>[1, 2]);
      final challenge = jsonEncode({
        'type': 'challenge',
        'nonce': base64Encode(Uint8List(32)),
      });
      final presence = jsonEncode({'type': 'presence', 'states': <Object>[]});
      expect(events[0].h, _hashText(challenge));
      expect(events[1].h, _hashText(presence));
      expect(events[0].toJson()['h'], events[0].h);
      expect(transport.inboundFrameCount, 2);
      expect(
        transport.inboundHash,
        _runningHash(<String>[challenge, presence]),
      );
    },
  );

  test(
    'server close reason is categorized without retaining free text',
    () async {
      final relay = await _CloseRelay.start();
      addTearDown(relay.close);
      final transport = await _connect(relay.url);
      addTearDown(transport.close);

      await relay.closePeer(4002, 'could contain payload text');
      await transport.transportClosed.timeout(const Duration(seconds: 1));

      expect(transport.closeDetails?.closeReason, 'present');
    },
  );

  test('local close records the exact initiating code path', () async {
    final relay = await _CloseRelay.start();
    addTearDown(relay.close);
    final transport = await _connect(relay.url);

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
    final transport = await _connect(relay.url, debugLog: log);

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

Future<WsTransport> _connect(String relayUrl, {DebugLog? debugLog}) async =>
    WsTransport.connect(
      relayUrl: relayUrl,
      peerPubkey: 'cGVlcg==',
      ed25519Key: await Ed25519().newKeyPair(),
      deviceId: 'close-diagnostics-device',
      debugLog: debugLog,
    );

/// Raw relay fixture that can terminate a valid WebSocket after an incomplete
/// server-to-client text frame has been written.
final class _AbruptRelay {
  _AbruptRelay._(this._server);

  static const _webSocketGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

  final ServerSocket _server;
  final _connected = Completer<void>();
  final _ready = Completer<void>();
  final _connections = <Socket>[];
  final _subscriptions = <StreamSubscription<Uint8List>>[];
  StreamSubscription<Socket>? _serverSubscription;
  Socket? _socket;

  String get url => 'ws://${_server.address.host}:${_server.port}';
  Future<void> get connected => _connected.future;

  static Future<_AbruptRelay> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final relay = _AbruptRelay._(server);
    relay._serverSubscription = server.listen(relay._accept);
    return relay;
  }

  void _accept(Socket socket) {
    _socket = socket;
    _connections.add(socket);
    final parser = _AbruptClientParser(
      socket: socket,
      onConnected: () {
        if (!_connected.isCompleted) _connected.complete();
      },
      onReady: () {
        if (!_ready.isCompleted) _ready.complete();
      },
    );
    _subscriptions.add(socket.listen(parser.add, onDone: parser.close));
  }

  Future<void> killMidFrame() async {
    await _ready.future;
    final socket = _socket!;
    // A non-final text frame with a declared payload that is never completed
    // makes the client parser observe an abnormal mid-message termination.
    socket.add(<int>[0x01, 0x7e, 0x00, 0x10, 0x7b]);
    await socket.flush();
    socket.destroy();
  }

  Future<void> sendFramingGarbage() async {
    await _connected.future;
    final socket = _socket!;
    // Opcode 3 is reserved and therefore invalid in a server data frame.
    socket.add(<int>[0x83, 0x00]);
    await socket.flush();
  }

  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    for (final connection in _connections) {
      connection.destroy();
    }
    await _serverSubscription?.cancel();
    await _server.close();
  }
}

/// Parse just enough client traffic to complete the transport readiness probe.
final class _AbruptClientParser {
  _AbruptClientParser({
    required this.socket,
    required this.onConnected,
    required this.onReady,
  });

  final Socket socket;
  final void Function() onConnected;
  final void Function() onReady;
  final _buffer = <int>[];
  bool _upgraded = false;
  bool _authenticated = false;

  void add(Uint8List bytes) {
    _buffer.addAll(bytes);
    if (!_upgraded && !_upgrade()) return;
    _parseFrames();
  }

  bool _upgrade() {
    final marker = const <int>[13, 10, 13, 10];
    final headerEnd = _indexOf(_buffer, marker);
    if (headerEnd < 0) return false;
    final request = latin1.decode(_buffer.sublist(0, headerEnd));
    final key = RegExp(
      r'^Sec-WebSocket-Key:\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(request)?.group(1)?.trim();
    if (key == null) throw StateError('missing WebSocket key');
    _buffer.removeRange(0, headerEnd + marker.length);
    final accept = base64Encode(
      crypto.sha1
          .convert(ascii.encode('$key${_AbruptRelay._webSocketGuid}'))
          .bytes,
    );
    socket.write(
      'HTTP/1.1 101 Switching Protocols\r\n'
      'Upgrade: websocket\r\n'
      'Connection: Upgrade\r\n'
      'Sec-WebSocket-Accept: $accept\r\n'
      '\r\n',
    );
    _upgraded = true;
    onConnected();
    return true;
  }

  void _parseFrames() {
    while (_buffer.length >= 2) {
      final first = _buffer[0];
      final second = _buffer[1];
      var cursor = 2;
      var length = second & 0x7f;
      if (length == 126) {
        if (_buffer.length < cursor + 2) return;
        length = (_buffer[cursor] << 8) | _buffer[cursor + 1];
        cursor += 2;
      } else if (length == 127) {
        if (_buffer.length < cursor + 8) return;
        length = 0;
        for (var i = 0; i < 8; i++) {
          length = (length << 8) | _buffer[cursor + i];
        }
        cursor += 8;
      }
      final masked = second & 0x80 != 0;
      final maskLength = masked ? 4 : 0;
      if (_buffer.length < cursor + maskLength + length) return;
      final mask = masked
          ? _buffer.sublist(cursor, cursor + maskLength)
          : const <int>[0, 0, 0, 0];
      cursor += maskLength;
      final payload = Uint8List.fromList(
        _buffer.sublist(cursor, cursor + length),
      );
      if (masked) {
        for (var i = 0; i < payload.length; i++) {
          payload[i] ^= mask[i & 3];
        }
      }
      _buffer.removeRange(0, cursor + length);
      if ((first & 0x0f) == 0x1) _handleText(payload);
    }
  }

  void _handleText(Uint8List payload) {
    final frame = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    switch (frame['type']) {
      case 'hello':
        _sendText(
          jsonEncode({
            'type': 'challenge',
            'nonce': base64Encode(Uint8List(32)),
          }),
        );
      case 'auth':
        _authenticated = true;
      case 'presence_check':
        if (_authenticated) {
          _sendText(jsonEncode({'type': 'presence', 'states': <Object>[]}));
          onReady();
        }
    }
  }

  void _sendText(String text) {
    final payload = utf8.encode(text);
    if (payload.length > 125) throw StateError('probe control frame too large');
    socket.add(<int>[0x81, payload.length, ...payload]);
  }

  void close() {}
}

const _fnvOffset = 0xcbf29ce484222325;
const _fnvPrime = 0x00000100000001b3;
const _fnvMask = 0xffffffffffffffff;

String _hashText(String text) => _hashBytes(utf8.encode(text));

String _hashBytes(List<int> bytes) => _formatHash(_hashValue(bytes));

int _hashValue(List<int> bytes) {
  var hash = _fnvOffset;
  for (final byte in bytes) {
    hash = ((hash ^ byte) * _fnvPrime) & _fnvMask;
  }
  return hash;
}

String _formatHash(int hash) =>
    BigInt.from(hash).toUnsigned(64).toRadixString(16).padLeft(16, '0');

String _runningHash(List<String> messages) {
  var running = _fnvOffset;
  for (var i = 0; i < messages.length; i++) {
    final frameHash = _hashValue(utf8.encode(messages[i]));
    final idx = i + 1;
    for (var shift = 0; shift < 64; shift += 8) {
      running = ((running ^ ((idx >> shift) & 0xff)) * _fnvPrime) & _fnvMask;
    }
    for (var shift = 0; shift < 64; shift += 8) {
      running =
          ((running ^ ((frameHash >> shift) & 0xff)) * _fnvPrime) & _fnvMask;
    }
  }
  return _formatHash(running);
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var matches = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return i;
  }
  return -1;
}

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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('queued data frames never follow the client Close frame', () async {
    final relay = await _RawFrameRelay.start();
    addTearDown(relay.close);
    final transport = await WsTransport.connect(
      relayUrl: relay.url,
      peerPubkey: 'cGVlcg==',
      ed25519Key: await Ed25519().newKeyPair(),
      deviceId: 'frame-order-device',
    );
    addTearDown(transport.close);

    // These large sends complete at the app seam while dart:io still owns the
    // actual socket flush. Closing immediately exercises the suspected queued
    // DATA-versus-Close race instead of merely sending after an idle drain.
    final payload = Uint8List(512 * 1024);
    final sends = <Future<void>>[
      transport.send(payload),
      transport.send(payload),
      transport.send(payload),
      transport.send(payload),
    ];
    final close = transport.closeWithPath(ChannelLocalClosePath.hedgeLoser);
    await Future.wait<void>([...sends, close]);
    await relay.clientCloseFrame.timeout(const Duration(seconds: 5));
    await relay.clientDone.timeout(const Duration(seconds: 5));

    final frames = relay.frames;
    final closeIndex = frames.indexWhere((frame) => frame.opcode == 0x8);
    expect(closeIndex, greaterThanOrEqualTo(0));
    expect(
      frames.where((frame) => frame.opcode == 0x1).length,
      greaterThanOrEqualTo(7),
      reason: 'hello/auth/readiness plus four queued envelopes must flush',
    );

    for (final frame in frames) {
      expect(frame.isFinal, isTrue);
      expect(frame.reservedBits, 0);
      expect(frame.masked, isTrue);
      expect(<int>{0x1, 0x8, 0x9, 0xA}, contains(frame.opcode));
      if (frame.opcode >= 0x8) {
        expect(frame.payloadLength, lessThanOrEqualTo(125));
      }
    }
    expect(
      frames.skip(closeIndex + 1).where((frame) => frame.opcode <= 0x2),
      isEmpty,
      reason: 'RFC 6455 forbids DATA after this client initiated Close',
    );
  });
}

final class _CapturedClientFrame {
  const _CapturedClientFrame({
    required this.firstByte,
    required this.secondByte,
    required this.payloadLength,
  });

  final int firstByte;
  final int secondByte;
  final int payloadLength;

  bool get isFinal => firstByte & 0x80 != 0;
  int get reservedBits => firstByte & 0x70;
  int get opcode => firstByte & 0x0F;
  bool get masked => secondByte & 0x80 != 0;
}

/// Minimal raw RFC 6455 server used only to observe client frame ordering.
///
/// It records header fields and payload lengths, never payload bytes. Payloads
/// are decoded transiently only far enough to complete the fixed relay
/// challenge/auth/readiness exchange required by [WsTransport.connect].
final class _RawFrameRelay {
  _RawFrameRelay._(this._server);

  static const _webSocketGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

  final ServerSocket _server;
  final _frames = <_CapturedClientFrame>[];
  final _clientClose = Completer<void>();
  final _clientDone = Completer<void>();
  final _connections = <Socket>[];
  final _subscriptions = <StreamSubscription<Uint8List>>[];
  StreamSubscription<Socket>? _serverSubscription;

  String get url => 'ws://${_server.address.host}:${_server.port}';
  List<_CapturedClientFrame> get frames => List.unmodifiable(_frames);
  Future<void> get clientCloseFrame => _clientClose.future;
  Future<void> get clientDone => _clientDone.future;

  static Future<_RawFrameRelay> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final relay = _RawFrameRelay._(server);
    relay._serverSubscription = server.listen(relay._accept);
    return relay;
  }

  void _accept(Socket socket) {
    _connections.add(socket);
    final parser = _RawClientParser(
      socket: socket,
      onFrame: (frame) {
        _frames.add(
          _CapturedClientFrame(
            firstByte: frame.firstByte,
            secondByte: frame.secondByte,
            payloadLength: frame.payload.length,
          ),
        );
        if (frame.opcode == 0x8 && !_clientClose.isCompleted) {
          _clientClose.complete();
        }
      },
    );
    _subscriptions.add(
      socket.listen(
        parser.add,
        onDone: () {
          parser.close();
          if (!_clientDone.isCompleted) _clientDone.complete();
        },
      ),
    );
  }

  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    for (final connection in _connections) {
      await connection.close();
    }
    await _serverSubscription?.cancel();
    await _server.close();
  }
}

final class _RawFrame {
  const _RawFrame({
    required this.firstByte,
    required this.secondByte,
    required this.payload,
  });

  final int firstByte;
  final int secondByte;
  final Uint8List payload;

  int get opcode => firstByte & 0x0F;
}

final class _RawClientParser {
  _RawClientParser({required this.socket, required this.onFrame});

  final Socket socket;
  final void Function(_RawFrame frame) onFrame;
  final _buffer = <int>[];
  bool _upgraded = false;
  bool _authenticated = false;

  void add(Uint8List bytes) {
    _buffer.addAll(bytes);
    if (!_upgraded && !_upgrade()) return;
    _parseFrames();
  }

  bool _upgrade() {
    final headerEnd = _indexOf(_buffer, const <int>[13, 10, 13, 10]);
    if (headerEnd < 0) return false;
    final request = latin1.decode(_buffer.sublist(0, headerEnd));
    final key = RegExp(
      r'^Sec-WebSocket-Key:\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(request)?.group(1)?.trim();
    if (key == null) throw StateError('missing WebSocket key');
    _buffer.removeRange(0, headerEnd + 4);
    final accept = base64Encode(
      crypto.sha1
          .convert(ascii.encode('$key${_RawFrameRelay._webSocketGuid}'))
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
    return true;
  }

  void _parseFrames() {
    while (_buffer.length >= 2) {
      final firstByte = _buffer[0];
      final secondByte = _buffer[1];
      var cursor = 2;
      var payloadLength = secondByte & 0x7F;
      if (payloadLength == 126) {
        if (_buffer.length < cursor + 2) return;
        payloadLength = (_buffer[cursor] << 8) | _buffer[cursor + 1];
        cursor += 2;
      } else if (payloadLength == 127) {
        if (_buffer.length < cursor + 8) return;
        payloadLength = 0;
        for (var i = 0; i < 8; i++) {
          payloadLength = (payloadLength << 8) | _buffer[cursor + i];
        }
        cursor += 8;
      }

      final masked = secondByte & 0x80 != 0;
      final maskBytes = masked ? 4 : 0;
      if (_buffer.length < cursor + maskBytes + payloadLength) return;
      final mask = masked
          ? _buffer.sublist(cursor, cursor + maskBytes)
          : const <int>[0, 0, 0, 0];
      cursor += maskBytes;
      final payload = Uint8List.fromList(
        _buffer.sublist(cursor, cursor + payloadLength),
      );
      if (masked) {
        for (var i = 0; i < payload.length; i++) {
          payload[i] ^= mask[i & 3];
        }
      }
      _buffer.removeRange(0, cursor + payloadLength);

      final frame = _RawFrame(
        firstByte: firstByte,
        secondByte: secondByte,
        payload: payload,
      );
      onFrame(frame);
      _handle(frame);
    }
  }

  void _handle(_RawFrame frame) {
    switch (frame.opcode) {
      case 0x1:
        final json =
            jsonDecode(utf8.decode(frame.payload)) as Map<String, dynamic>;
        switch (json['type']) {
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
            }
        }
      case 0x8:
        _sendFrame(0x88, frame.payload);
      case 0x9:
        _sendFrame(0x8A, frame.payload);
    }
  }

  void _sendText(String text) => _sendFrame(0x81, utf8.encode(text));

  void _sendFrame(int firstByte, List<int> payload) {
    if (payload.length > 125) {
      throw StateError('test relay only emits small control/text frames');
    }
    socket.add(<int>[firstByte, payload.length, ...payload]);
  }

  void close() {}
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

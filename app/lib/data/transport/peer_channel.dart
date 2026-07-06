// PlainPeerChannel — protocol message channel without E2E cipher.
//
// Wraps a connected PeerTransport. After pairing, use this to exchange
// ClientMessage / ServerMessage with the Pi extension.
//
//   send(ClientMessage)   → JSON          → transport.send()
//   serverMessages stream ← transport.receive() → JSON → ServerMessage

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/transport/channel.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/protocol/codec.dart';
// ControlInbound + IControlLink come from these.
import 'package:app/protocol/protocol.dart';

class PeerChannelError implements Exception {
  final String message;
  const PeerChannelError(this.message);

  @override
  String toString() => 'PeerChannelError: $message';
}

class PlainPeerChannel implements IChannel, IControlLink {
  final PeerTransport _transport;
  final DebugLog? _debugLog;

  final _controller = StreamController<ServerMessage>.broadcast();
  bool _started = false;
  bool _closed = false;

  PlainPeerChannel({required PeerTransport transport, DebugLog? debugLog})
    : _transport = transport,
      _debugLog = debugLog;

  // ---- IControlLink — forwards to the underlying transport when it
  //      supports raw control frames (production: WsTransport). For
  //      non-WS transports (tests / in-memory), returns an empty stream
  //      and silently drops outbound control frames.
  @override
  Stream<ControlInbound> get controlFrames {
    final t = _transport;
    if (t is IControlLink) return (t as IControlLink).controlFrames;
    return const Stream.empty();
  }

  @override
  void sendControl(Map<String, dynamic> json) {
    final t = _transport;
    if (t is IControlLink) (t as IControlLink).sendControl(json);
  }

  /// Plan 17 — propagate the active Pi-side room to the underlying
  /// transport so subsequent `send`s carry the right outer `room` field.
  /// No-op when the transport doesn't support it (in-memory test fakes).
  void setActiveRoom(String roomId) {
    final t = _transport;
    try {
      (t as dynamic).setActiveRoom(roomId);
    } catch (_) {
      // Non-WS transports don't track rooms — fine to ignore.
    }
  }

  @override
  Stream<ServerMessage> get serverMessages {
    if (!_started) {
      _started = true;
      _receiveLoop();
    }
    return _controller.stream;
  }

  @override
  Future<void> send(ClientMessage msg) async {
    final bytes = Uint8List.fromList(
      utf8.encode(encodeClient(msg).trimRight()),
    );
    await _transport.send(bytes);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _transport.close();
    if (!_controller.isClosed) await _controller.close();
  }

  Future<void> _receiveLoop() async {
    try {
      while (!_closed) {
        final bytes = await _transport.receive();
        _handleFrame(bytes);
      }
    } catch (_) {
      if (!_controller.isClosed) await _controller.close();
    }
  }

  void _handleFrame(Uint8List bytes) {
    try {
      final msg = decodeServer(utf8.decode(bytes));
      if (!_controller.isClosed) _controller.add(msg);
    } on UnsupportedTypeException {
      _logPeerFrame(
        PeerFrameEvent(
          ts: DateTime.now(),
          kind: 'unsupported_type',
          bytes: bytes.length,
        ),
      );
      // Forward-compat: surface unknown server types as ErrorMessage.
      if (!_controller.isClosed) {
        _controller.add(
          ErrorMessage(
            sessionId: '',
            code: 'unsupported_type',
            message: 'unknown server type',
          ),
        );
      }
    } on Object catch (e) {
      _logPeerFrame(
        PeerFrameEvent(
          ts: DateTime.now(),
          kind: 'malformed',
          bytes: bytes.length,
          error: _shortReason(e),
        ),
      );
      // Malformed frame — drop silently. Previous diagnostic logging
      // for cast / decode errors lived here; we trust upstream codecs
      // now that the channel pipeline is stable.
    }
  }

  void _logPeerFrame(PeerFrameEvent event) => _debugLog?.log(event);

  static String _shortReason(Object raw) {
    // Privacy: use the exception's runtimeType (e.g. 'FormatException',
    // 'TypeError') rather than its message — a decode error's toString()
    // can include the raw bytes/content that failed to decode. Fall back to
    // a constant (never raw.toString()) so the invariant holds even if
    // runtimeType is somehow empty.
    final type = raw.runtimeType.toString();
    return type.isEmpty ? 'unknown_error' : (type.length <= 120 ? type : '${type.substring(0, 120)}…');
  }
}

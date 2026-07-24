// Peer-channel adapters over the byte-level PeerTransport.
//
// PlainPeerChannel is restricted to the pre-key pairing exchange. Established
// peers use SecurePeerChannel, which seals the same typed protocol messages.

import 'dart:async';
import 'dart:convert';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/secure_channel.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/codec.dart';
// ControlInbound + IControlLink come from these.
import 'package:app/protocol/protocol.dart';
import 'package:flutter/foundation.dart';

/// Describe a peer-channel failure safe to show or log without raw frame data.
class PeerChannelError implements Exception {
  final String message;
  const PeerChannelError(this.message);

  @override
  String toString() => 'PeerChannelError: $message';
}

/// Adapt one connected [PeerTransport] into typed peer and relay-control streams.
///
/// Starts receiving on the first server-message subscription, forwards unknown
/// wire types as typed errors, and owns transport/controller closure.
class PlainPeerChannel implements IChannel, IControlLink, IActiveRoomTarget {
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

  /// Propagate the active Pi-side room to a room-aware byte transport.
  @override
  void setActiveRoom(String roomId) {
    if (_transport case IActiveRoomTarget target) {
      target.setActiveRoom(roomId);
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
    return type.isEmpty
        ? 'unknown_error'
        : (type.length <= 120 ? type : '${type.substring(0, 120)}…');
  }
}

/// Maximum protected outbound frames retained while persistence is pending.
const int maxPendingOwnerOutboundFrames = 512;

/// Maximum serialized outbound bytes retained while persistence is pending.
const int maxPendingOwnerOutboundBytes = 16 * 1024 * 1024;

/// Protect established owner traffic while preserving control/room capabilities.
///
/// Sequence high-water marks are written before outbound transport use and
/// before inbound delivery. Outbound persistence work is admitted against a
/// bounded frame/byte budget; overflow closes the channel so reconnect and
/// session sync recover instead of silently dropping a streaming suffix.
/// Invalid inbound frames are dropped and audited; five consecutive failures
/// close the transport so recovery cannot downgrade to plaintext.
class SecurePeerChannel implements IChannel, IControlLink, IActiveRoomTarget {
  SecurePeerChannel({
    required PeerTransport transport,
    required PairingStorage storage,
    required PeerRecord peer,
    DebugLog? debugLog,
    int failureThreshold = 5,
    int maxPendingOutboundFrames = maxPendingOwnerOutboundFrames,
    int maxPendingOutboundBytes = maxPendingOwnerOutboundBytes,
  }) : assert(maxPendingOutboundFrames > 0),
       assert(maxPendingOutboundBytes > 0),
       _transport = transport,
       _storage = storage,
       _remoteEpk = peer.remoteEpk,
       _debugLog = debugLog,
       _failureThreshold = failureThreshold,
       _maxPendingOutboundFrames = maxPendingOutboundFrames,
       _maxPendingOutboundBytes = maxPendingOutboundBytes,
       _sendKey = _decodeKey(peer.channel?.sendKey),
       _receiveKey = _decodeKey(peer.channel?.receiveKey),
       _sendSequence = _requireChannel(peer).sendSequence,
       _receiveSequence = _requireChannel(peer).receiveSequence {
    if (transport case PeerTransportCloseSignal signal) {
      unawaited(signal.transportClosed.then((_) => _onTransportClosed()));
    }
  }

  final PeerTransport _transport;
  final PairingStorage _storage;
  final String _remoteEpk;
  final DebugLog? _debugLog;
  final int _failureThreshold;
  final int _maxPendingOutboundFrames;
  final int _maxPendingOutboundBytes;
  final Uint8List _sendKey;
  final Uint8List _receiveKey;
  final _controller = StreamController<ServerMessage>.broadcast();

  int _sendSequence;
  int _receiveSequence;
  int _consecutiveFailures = 0;
  int _pendingOutboundFrames = 0;
  int _pendingOutboundBytes = 0;
  bool _started = false;
  bool _closed = false;
  Future<void> _sendTail = Future<void>.value();
  Future<void> _stateTail = Future<void>.value();

  @visibleForTesting
  int get debugPendingOutboundFrames => _pendingOutboundFrames;

  @visibleForTesting
  int get debugPendingOutboundBytes => _pendingOutboundBytes;

  @visibleForTesting
  Future<void> debugWhenOutboundIdle() => _sendTail;

  @override
  Stream<ControlInbound> get controlFrames {
    final transport = _transport;
    return transport is IControlLink
        ? (transport as IControlLink).controlFrames
        : const Stream.empty();
  }

  @override
  void sendControl(Map<String, dynamic> json) {
    final transport = _transport;
    if (transport is IControlLink) {
      (transport as IControlLink).sendControl(json);
    }
  }

  @override
  void setActiveRoom(String roomId) {
    if (_transport case IActiveRoomTarget target) {
      target.setActiveRoom(roomId);
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
  Future<void> send(ClientMessage msg) {
    if (_closed) {
      return Future<void>.error(const PeerChannelError('channel is closed'));
    }
    final json = encodeClient(msg).trimRight();
    final jsonBytes = utf8.encode(json).length;
    if (_pendingOutboundFrames >= _maxPendingOutboundFrames ||
        jsonBytes > _maxPendingOutboundBytes - _pendingOutboundBytes) {
      _debugLog?.log(
        PeerFrameEvent(
          ts: DateTime.now(),
          kind: 'outbound_overflow',
          bytes: jsonBytes,
        ),
      );
      return _closeForOutboundOverflow();
    }

    // Account before allocating the continuation that retains [json].
    _pendingOutboundFrames++;
    _pendingOutboundBytes += jsonBytes;
    final operation = _sendTail.then((_) => _sendOne(json));
    _sendTail = operation.catchError((Object _) {}).whenComplete(() {
      _pendingOutboundFrames--;
      _pendingOutboundBytes -= jsonBytes;
    });
    return operation;
  }

  Future<void> _closeForOutboundOverflow() async {
    await close();
    throw const PeerChannelError('owner-channel outbound queue overflow');
  }

  Future<void> _sendOne(String json) async {
    if (_closed) throw const PeerChannelError('channel is closed');
    if (_sendSequence == 0x7fffffffffffffff) {
      await close();
      throw const PeerChannelError('owner-channel sequence exhausted');
    }
    final next = _sendSequence + 1;
    final frame = await sealOwnerChannelFrame(
      key: _sendKey,
      sequence: next,
      json: json,
    );
    _sendSequence = next;
    // Reserve the sequence durably before the byte transport can expose it.
    // A failed send leaves a harmless gap because the sequence is transmitted.
    try {
      await _persistState();
    } on Object {
      await close();
      rethrow;
    }
    if (_closed) throw const PeerChannelError('channel is closed');
    await _transport.send(frame);
  }

  Future<void> _receiveLoop() async {
    try {
      while (!_closed) {
        final bytes = await _transport.receive();
        await _handleSecureFrame(bytes);
      }
    } on Object {
      if (!_closed) {
        await close();
      } else if (!_controller.isClosed) {
        await _controller.close();
      }
    }
  }

  Future<void> _handleSecureFrame(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.first != 0x01) {
      await _recordFailure('plaintext_post_key', bytes.length);
      return;
    }
    final opened = await openOwnerChannelFrame(
      key: _receiveKey,
      frame: bytes,
      lastSequence: _receiveSequence,
    );
    if (opened == null) {
      await _recordFailure('authentication_failed', bytes.length);
      return;
    }
    final ServerMessage message;
    try {
      message = decodeServer(opened.json);
    } on UnsupportedTypeException {
      await _recordFailure('unsupported_type', bytes.length);
      return;
    } on Object catch (error) {
      await _recordFailure(
        'malformed',
        bytes.length,
        error: PlainPeerChannel._shortReason(error),
      );
      return;
    }
    _receiveSequence = opened.sequence;
    // Persistence failure is a local security-boundary failure, not an
    // attacker frame. Let it escape to the receive loop, which detaches.
    await _persistState();
    if (_closed) return;
    _consecutiveFailures = 0;
    if (!_controller.isClosed) _controller.add(message);
  }

  Future<void> _recordFailure(String kind, int bytes, {String? error}) async {
    _debugLog?.log(
      PeerFrameEvent(
        ts: DateTime.now(),
        kind: kind,
        bytes: bytes,
        error: error,
      ),
    );
    _consecutiveFailures++;
    if (_consecutiveFailures >= _failureThreshold) await close();
  }

  Future<void> _persistState() {
    final snapshot = OwnerChannelState(
      sendKey: base64.encode(_sendKey),
      receiveKey: base64.encode(_receiveKey),
      sendSequence: _sendSequence,
      receiveSequence: _receiveSequence,
    );
    final operation = _stateTail.then(
      (_) => _storage.saveChannelState(_remoteEpk, snapshot),
    );
    _stateTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _onTransportClosed() async {
    if (_closed) return;
    _closed = true;
    if (!_controller.isClosed) await _controller.close();
    try {
      await _transport.close();
    } on Object {
      // The close signal already established transport loss. Cleanup is
      // best-effort and must not hide the channel-facing close event.
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _transport.close();
    } finally {
      if (!_controller.isClosed) await _controller.close();
    }
  }

  static OwnerChannelState _requireChannel(PeerRecord peer) {
    final channel = peer.channel;
    if (channel == null) {
      throw const PeerChannelError('paired peer has no owner-channel keys');
    }
    return channel;
  }

  static Uint8List _decodeKey(String? encoded) {
    if (encoded == null) {
      throw const PeerChannelError('paired peer has no owner-channel keys');
    }
    try {
      final bytes = base64.decode(encoded);
      if (bytes.length != 32) throw const FormatException();
      return Uint8List.fromList(bytes);
    } on FormatException {
      throw const PeerChannelError('paired peer has invalid owner-channel key');
    }
  }
}

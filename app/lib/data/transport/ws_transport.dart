// WebSocket-based PeerTransport.
//
// Flow per connection:
//   1. Connect to relay WS
//   2. Ed25519 challenge-response (hello → challenge → auth)
//   3. After auth, two parallel streams of inbound frames:
//        - envelope frames `{peer, ct}` → decoded to the peer queue
//        - control frames (top-level `type`, no `peer`) → control stream
//      Outbound `subscribe_presence` / `presence_check` go raw too.
//
// `peer` is standard base64 of the destination's Ed25519 pubkey (matches
// the relay registry, populated from the peer's hello). `ct` is base64 of
// the inner-envelope bytes (plain JSON post-rollback, see plan 06).

import 'dart:async';
import 'dart:convert';

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/data/transport/relay_frame_decoder.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/protocol/protocol.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../pairing/pair_request_flow.dart';

/// Domain-separation prefix for relay-auth signatures. Appended before the
/// relay-provided nonce before signing, so the owner key cannot be abused as a
/// cross-protocol signing oracle. Dart has no schema codegen path; the shared
/// auth-domain vector test keeps this local value aligned with the schema.
final List<int> relayAuthDomainPrefix = utf8.encode(
  'outpost-pi-relay-auth-v1\n',
);

/// Build the exact bytes covered by a relay-auth signature.
Uint8List relayAuthSigningBytes(List<int> nonce) =>
    Uint8List.fromList([...relayAuthDomainPrefix, ...nonce]);

/// Describe WebSocket transport failure at the relay boundary.
class WsTransportError implements Exception {
  final String message;
  const WsTransportError(this.message);

  @override
  String toString() => 'WsTransportError: $message';
}

/// Maximum data-plane frames buffered while a peer channel is busy.
const int maxPendingWsInboundFrames = 256;

/// Maximum data-plane bytes buffered while a peer channel is busy.
const int maxPendingWsInboundBytes = 8 * 1024 * 1024;

const int _wsOverflowAuditSummaryEvents = 100;
const Duration _wsOverflowAuditSummaryInterval = Duration(seconds: 5);

/// Carry peer envelopes and relay control frames over one authenticated WebSocket.
///
/// [connect] completes only after challenge-response authentication; [close]
/// owns the socket subscription, bounded peer queue, and control stream
/// lifecycle. Relay control frames bypass the data queue and therefore remain
/// available while secure-channel persistence is blocked.
class WsTransport
    implements
        PeerTransport,
        PeerTransportCloseSignal,
        IControlLink,
        IActiveRoomTarget {
  final WebSocketChannel _ws;
  final DebugLog? _debugLog;
  late final WsInboundMessageQueue _queue;
  final _controlController = StreamController<ControlInbound>.broadcast();
  final _transportClosedCompleter = Completer<void>();
  int _droppedQueueFrames = 0;
  int _droppedQueueBytes = 0;
  bool _queueOverflowAuditEmitted = false;
  bool _closed = false;
  Timer? _queueOverflowAuditTimer;

  WsTransport._(
    this._ws, {
    DebugLog? debugLog,
    String activeRoom = 'main',
    int maxPendingInboundFrames = maxPendingWsInboundFrames,
    int maxPendingInboundBytes = maxPendingWsInboundBytes,
  }) : _debugLog = debugLog,
       _activeRoom = activeRoom {
    _queue = WsInboundMessageQueue(
      maxFrames: maxPendingInboundFrames,
      maxBytes: maxPendingInboundBytes,
      onOverflow: _recordQueueOverflow,
    );
  }

  // Connect, authenticate with relay, and return a ready transport.
  //
  // [activeRoom] is the Pi-side destination room envelopes are routed to
  // AND the room inbound envelopes are demuxed against from the very first
  // post-auth frame. The relay may push envelopes immediately after auth,
  // before the caller gets a chance to call `setActiveRoom` — so the room
  // must be correct from construction, not defaulted to `'main'` and patched
  // after (see `story-fix-transport-active-room-reestablishment-on-reconnect`
  // for the room-mismatch-drop ring-log evidence that motivated this).
  static Future<WsTransport> connect({
    required String relayUrl,
    required String peerPubkey, // base64 standard or url — destination peer
    required SimpleKeyPair ed25519Key, // this device's Ed25519 long-term key
    required String
    deviceId, // per-install id — relay closes prior same-device conns on reconnect
    String activeRoom = 'main',
    DebugLog? debugLog,
  }) async {
    // Plan-18 follow-up — set a WS-level pingInterval (RFC 6455
    // control frames). This keeps the TCP connection alive through
    // NAT / corporate proxies that aggressively close idle sockets,
    // and surfaces a dead WS as `onDone` / `onError` instead of
    // letting it silently linger until the next user action. The
    // protocol-level Ping/Pong handled by ConnectionManager covers
    // app↔Pi liveness; this one covers app↔relay TCP liveness.
    //
    // Mobile-tuned (story-mobile-connection-flapping-drops-identity-frames):
    // 45s, deliberately LOOSER than the relay's own 25s keepalive
    // (`relay/src/handlers/peer.rs:130`). The previous 20s was TIGHTER than
    // the relay's 25s, so the app tore down connections the relay still
    // considered alive — a single missed pong (mobile network blip: cell
    // handoff, wifi roaming, Doze micro-sleep, transient latency) closed the
    // socket → onDone → _onChannelLost → reconnect storm. The reconnect's
    // `onAppFrameObserved()` resets the backoff to 1s on any inbound frame,
    // so brief connections kept the backoff from ramping → 3 overlapping
    // auths in 12s (superseded_existing=true). 45s gives mobile latency
    // tolerance while still detecting a genuinely dead connection within a
    // reasonable window; the relay's 25s keepalive governs NAT idle timers.
    // Accept http(s) URLs in the user-facing form but always speak
    // ws(s) on the wire — IOWebSocketChannel rejects http schemes.
    final WebSocketChannel ws = IOWebSocketChannel.connect(
      Uri.parse(toWsRelayUrl(relayUrl)),
      pingInterval: const Duration(seconds: 45),
    );
    final transport = WsTransport._(
      ws,
      debugLog: debugLog,
      activeRoom: activeRoom,
    );

    final challengeCompleter = Completer<String>();
    bool authDone = false;

    final sub = ws.stream.listen(
      (raw) {
        // Volume probe: log every frame the relay pushes onto this
        // socket so we can spot firehose patterns (e.g. presence
        // churn, repeated room snapshots) by counting prefix
        // occurrences — body kept compact so the log stays grep-able
        // even when the relay is chatty.
        final rawStr = raw is String ? raw : raw.toString();
        if (!authDone) {
          final rawBytes = relayUtf8ByteLength(
            rawStr,
            maxBytes: relayMaxPreAuthFrameBytes,
          );
          debugPrint('[ws-in] bytes=$rawBytes stage=preauth');
          transport._logWsIn(
            WsInEvent(
              ts: DateTime.now(),
              bytes: rawBytes,
              kind: 'preauth',
              stage: 'preauth',
            ),
          );
          if (!challengeCompleter.isCompleted) {
            if (rawBytes > relayMaxPreAuthFrameBytes) {
              challengeCompleter.completeError(
                RelayFrameDecodeException(
                  RelayFrameDecodeFailure.tooLarge,
                  rawBytes,
                ),
              );
            } else {
              challengeCompleter.complete(rawStr);
            }
          }
          return;
        }
        final decision = demuxPostAuthInboundFrame(
          raw: rawStr,
          activeRoom: transport._activeRoom,
        );

        switch (decision.kind) {
          case WsInboundFrameKind.enqueue:
            final envelopeBytes = decision.envelopeBytes!;
            // demuxPostAuthInboundFrame only returns `enqueue` after a
            // successful _b64Decode (any decode failure throws and is caught
            // → dropMalformed), so envelopeBytes is always non-null here.
            // The previous `envelopeBytes == null` defensive branch was
            // unreachable dead code; removed during review.
            if (transport._queue.add(envelopeBytes)) {
              debugPrint(
                '[ws-in] kind=envelope ct.bytes=${envelopeBytes.length}',
              );
              transport._logWsIn(
                WsInEvent(
                  ts: DateTime.now(),
                  bytes: envelopeBytes.length,
                  kind: 'envelope',
                  stage: 'enqueue',
                ),
              );
            }
            return;

          case WsInboundFrameKind.dropMissingRoom:
            debugPrint('[ws-in] kind=envelope DROPPED (missing-room)');
            transport._logWsIn(
              WsInEvent(
                ts: DateTime.now(),
                bytes: rawStr.length,
                kind: 'envelope',
                stage: 'missing-room',
              ),
            );
            return;

          case WsInboundFrameKind.dropRoomMismatch:
            debugPrint(
              '[ws-in] kind=envelope sender_room=${decision.senderRoom} '
              'DROPPED (room-mismatch)',
            );
            transport._logWsIn(
              WsInEvent(
                ts: DateTime.now(),
                bytes: rawStr.length,
                kind: 'envelope',
                stage: 'room-mismatch',
                senderRoom: decision.senderRoom,
              ),
            );
            return;

          case WsInboundFrameKind.control:
            if (!transport._controlController.isClosed) {
              // demuxPostAuthInboundFrame returns `control` only when
              // ControlInbound.tryFromJson returned non-null; unknown types
              // return null → demux returns dropMalformed. So decision.control
              // is always non-null here. The previous `control == null`
              // defensive branch was unreachable dead code; removed during
              // review. (A typed-but-malformed control frame throws inside
              // tryFromJson → caught by the demux → dropMalformed.)
              final control = decision.control!;
              debugPrint(
                '[ws-in] bytes=${rawStr.length} kind=control '
                'type=${decision.controlType}',
              );
              transport._logWsIn(
                WsInEvent(
                  ts: DateTime.now(),
                  bytes: rawStr.length,
                  kind: 'control',
                  stage: 'accepted',
                  controlType: decision.controlType,
                ),
              );
              transport._controlController.add(control);
            }
            return;

          case WsInboundFrameKind.dropMalformed:
            debugPrint(
              '[ws-in] bytes=${rawStr.length} kind=malformed '
              'DROPPED err=${decision.error}',
            );
            transport._logWsIn(
              WsInEvent(
                ts: DateTime.now(),
                bytes: rawStr.length,
                kind: 'malformed',
                stage: 'dropped',
                error: decision.error,
              ),
            );
            return;
        }
      },
      onError: (e) {
        if (!challengeCompleter.isCompleted) {
          challengeCompleter.completeError(e);
        }
        transport._queue.error(e);
        transport._flushQueueOverflowAudit();
        transport._signalTransportClosed();
        if (!transport._controlController.isClosed) {
          transport._controlController.close();
        }
      },
      onDone: () {
        if (!challengeCompleter.isCompleted) {
          challengeCompleter.completeError(
            const WsTransportError('WS closed during auth'),
          );
        }
        transport._queue.close();
        transport._flushQueueOverflowAudit();
        transport._signalTransportClosed();
        if (!transport._controlController.isClosed) {
          transport._controlController.close();
        }
      },
    );

    try {
      // 1. Hello (standard base64 — matches relay registry format).
      // Plan 17: app is a client (no cwd) and always announces itself
      // on the canonical 'main' room. Pi-side hellos include their own
      // room_id (one per cwd) AND room_meta; that's not our concern here.
      final pub = await ed25519Key.extractPublicKey();
      ws.sink.add(
        jsonEncode({
          'type': 'hello',
          'pubkey': base64.encode(pub.bytes),
          'device_id': deviceId,
          'room_id': 'main',
        }),
      );

      // 2. Challenge
      final challengeRaw = await challengeCompleter.future;
      final nonce = decodeRelayChallenge(challengeRaw);

      // 3. Auth — domain-separated signature over the relay nonce.
      // Signing the bare nonce with the long-term owner key would create a
      // cross-protocol signing oracle (a malicious relay could harvest
      // signatures on attacker-chosen bytes). The fixed prefix binds the
      // signature to the relay-auth context so it is useless as a forgery of
      // any other protocol's signature. MUST stay in lockstep with the relay's
      // `verify_auth` (relay/src/auth/challenge.rs).
      final sig = await Ed25519().sign(
        relayAuthSigningBytes(nonce),
        keyPair: ed25519Key,
      );
      ws.sink.add(
        jsonEncode({'type': 'auth', 'sig': base64.encode(sig.bytes)}),
      );
      authDone = true;

      transport._peerPubkey = _normalizeToStandard(peerPubkey);
      transport._sub = sub;
      return transport;
    } catch (e) {
      await sub.cancel();
      await ws.sink.close();
      rethrow;
    }
  }

  String _peerPubkey = '';
  StreamSubscription? _sub;

  void _logWsIn(WsInEvent event) => _debugLog?.log(event);

  void _recordQueueOverflow(int bytes) {
    _droppedQueueFrames++;
    _droppedQueueBytes += bytes;
    if (!_queueOverflowAuditEmitted ||
        _droppedQueueFrames >= _wsOverflowAuditSummaryEvents) {
      _flushQueueOverflowAudit();
      return;
    }
    _queueOverflowAuditTimer ??= Timer(
      _wsOverflowAuditSummaryInterval,
      _flushQueueOverflowAudit,
    );
  }

  void _flushQueueOverflowAudit() {
    _queueOverflowAuditTimer?.cancel();
    _queueOverflowAuditTimer = null;
    if (_droppedQueueFrames == 0) return;
    _logWsIn(
      WsInEvent(
        ts: DateTime.now(),
        bytes: _droppedQueueBytes,
        count: _droppedQueueFrames,
        kind: 'envelope',
        stage: 'queue-overflow',
      ),
    );
    _droppedQueueFrames = 0;
    _droppedQueueBytes = 0;
    _queueOverflowAuditEmitted = true;
  }

  void _signalTransportClosed() {
    if (!_transportClosedCompleter.isCompleted) {
      _transportClosedCompleter.complete();
    }
  }

  @override
  Future<void> get transportClosed => _transportClosedCompleter.future;

  /// Active target room on the Pi side. The outer envelope embeds this so
  /// the Pi can route the inner message to the right per-cwd session, AND
  /// the inbound demux compares each envelope's `room` against it. Set from
  /// construction (see `connect`'s `activeRoom`) so post-auth frames are
  /// demuxed against the correct room from frame 1; `setActiveRoom` only
  /// changes it for runtime room switches (`switchRoom`).
  String _activeRoom;

  /// Override the destination room (Pi side). The app remains on the
  /// 'main' room itself (that's what we sent in `hello.room_id`).
  @override
  void setActiveRoom(String room) {
    if (room == _activeRoom) {
      return;
    }
    _activeRoom = room;
  }

  @override
  Future<void> send(Uint8List data) async {
    _ws.sink.add(
      jsonEncode({
        'peer': _peerPubkey,
        'room': _activeRoom,
        'ct': base64.encode(data),
      }),
    );
  }

  @override
  Future<Uint8List> receive() => _queue.next();

  // ---- IControlLink --------------------------------------------------------

  @override
  Stream<ControlInbound> get controlFrames => _controlController.stream;

  @override
  void sendControl(Map<String, dynamic> json) {
    _ws.sink.add(jsonEncode(json));
  }

  // -------------------------------------------------------------------------

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _queue.close();
    _flushQueueOverflowAudit();
    _signalTransportClosed();
    await _sub?.cancel();
    await _ws.sink.close();
    if (!_controlController.isClosed) await _controlController.close();
  }
}

/// Classify an authenticated relay frame before it reaches peer or control state.
@visibleForTesting
enum WsInboundFrameKind {
  enqueue,
  dropMissingRoom,
  dropRoomMismatch,
  control,
  dropMalformed,
}

/// Carry the validated demultiplexing result without reparsing the raw frame.
@visibleForTesting
final class WsInboundFrameDecision {
  final WsInboundFrameKind kind;
  final Uint8List? envelopeBytes;
  final ControlInbound? control;
  final String? senderRoom;
  final String? controlType;
  final String? error;

  const WsInboundFrameDecision({
    required this.kind,
    this.envelopeBytes,
    this.control,
    this.senderRoom,
    this.controlType,
    this.error,
  });
}

/// Validate and route one post-auth relay frame for the active Pi room.
///
/// Invalid JSON, unknown control types, and missing or mismatched room envelopes
/// return an explicit drop decision so untrusted data cannot reach consumers.
@visibleForTesting
WsInboundFrameDecision demuxPostAuthInboundFrame({
  required String raw,
  required String activeRoom,
  int maxRawBytes = relayMaxRawMessageBytes,
  int maxDecodedPayloadBytes = relayDefaultMaxDecodedBytes,
}) {
  final decoded = decodeRelayInboundFrame(
    raw,
    maxRawBytes: maxRawBytes,
    maxDecodedPayloadBytes: maxDecodedPayloadBytes,
  );
  if (decoded case RejectedRelayFrame(:final reason)) {
    return WsInboundFrameDecision(
      kind: WsInboundFrameKind.dropMalformed,
      error: reason.name,
    );
  }
  final accepted = decoded as DecodedRelayFrame;

  switch (accepted.frame) {
    case RelayOuterEnvelopeDto(:final room):
      if (room == null || room.isEmpty) {
        return const WsInboundFrameDecision(
          kind: WsInboundFrameKind.dropMissingRoom,
        );
      }
      if (room != activeRoom) {
        return WsInboundFrameDecision(
          kind: WsInboundFrameKind.dropRoomMismatch,
          senderRoom: room,
        );
      }
      return WsInboundFrameDecision(
        kind: WsInboundFrameKind.enqueue,
        envelopeBytes: accepted.decodedPayload,
      );
    case RelayServerControlFrameDto(:final type):
      return WsInboundFrameDecision(
        kind: WsInboundFrameKind.control,
        control: accepted.control,
        controlType: type,
      );
  }
}

// ---------------------------------------------------------------------------

/// Bounded FIFO for authenticated relay data-plane payloads.
///
/// Admission drops only the new frame and reports only its byte count to the
/// overflow callback. Closing clears accepted data and preempts future reads so
/// transport loss is never hidden behind stale frames.
@visibleForTesting
final class WsInboundMessageQueue {
  WsInboundMessageQueue({
    required this.maxFrames,
    required this.maxBytes,
    void Function(int bytes)? onOverflow,
  }) : assert(maxFrames > 0),
       assert(maxBytes > 0),
       _onOverflow = onOverflow;

  final int maxFrames;
  final int maxBytes;
  final void Function(int bytes)? _onOverflow;
  final _buf = <Uint8List>[];
  final _waiters = <Completer<Uint8List>>[];
  int _pendingBytes = 0;
  bool _closed = false;

  @visibleForTesting
  int get pendingFrames => _buf.length;

  @visibleForTesting
  int get pendingBytes => _pendingBytes;

  bool add(Uint8List msg) {
    if (_closed) return false;
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(msg);
      return true;
    }
    if (_buf.length >= maxFrames || msg.length > maxBytes - _pendingBytes) {
      _onOverflow?.call(msg.length);
      return false;
    }
    _buf.add(msg);
    _pendingBytes += msg.length;
    return true;
  }

  void error(Object e) {
    if (_closed) return;
    _closed = true;
    _clearBuffered();
    for (final waiter in _waiters) {
      waiter.completeError(e);
    }
    _waiters.clear();
  }

  void close() {
    error(const WsTransportError('transport closed'));
  }

  Future<Uint8List> next() {
    if (_closed) {
      return Future.error(const WsTransportError('transport closed'));
    }
    if (_buf.isNotEmpty) {
      final message = _buf.removeAt(0);
      _pendingBytes -= message.length;
      return Future.value(message);
    }
    final completer = Completer<Uint8List>();
    _waiters.add(completer);
    return completer.future;
  }

  void _clearBuffered() {
    _buf.clear();
    _pendingBytes = 0;
  }
}

// Relay registry uses standard base64 (from each peer's hello). QR/storage
// may carry url-safe encoding — re-encode to standard so the relay matches.
String _normalizeToStandard(String pubkey) {
  try {
    final pad = (4 - pubkey.length % 4) % 4;
    final bytes = base64Url.decode(pubkey + '=' * pad);
    return base64.encode(bytes);
  } catch (_) {
    return pubkey;
  }
}

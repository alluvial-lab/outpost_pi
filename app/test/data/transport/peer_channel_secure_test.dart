import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/secure_channel.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

class _QueueTransport implements PeerTransport {
  final _inbound = <Uint8List>[];
  final _waiters = <Completer<Uint8List>>[];
  final List<Uint8List> sent = <Uint8List>[];
  bool closed = false;

  void push(List<int> bytes) {
    final value = Uint8List.fromList(bytes);
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(value);
    } else {
      _inbound.add(value);
    }
  }

  @override
  Future<void> send(Uint8List data) async => sent.add(data);

  @override
  Future<Uint8List> receive() {
    if (_inbound.isNotEmpty) return Future.value(_inbound.removeAt(0));
    final completer = Completer<Uint8List>();
    _waiters.add(completer);
    return completer.future;
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('transport closed'));
      }
    }
    _waiters.clear();
  }
}

class _ChannelStorage extends PairingStorage {
  final List<OwnerChannelState> states = <OwnerChannelState>[];

  @override
  Future<void> saveChannelState(
    String remoteEpk,
    OwnerChannelState channel,
  ) async {
    states.add(channel);
  }
}

class _RecordingDebugLog implements DebugLog {
  final List<DebugEvent> events = <DebugEvent>[];

  @override
  void log(DebugEvent event) => events.add(event);

  @override
  Future<String?> export() async => null;

  @override
  Future<void> clear() async => events.clear();

  @override
  void dispose() {}
}

final _sendKey = Uint8List.fromList(List<int>.generate(32, (index) => index));
final _receiveKey = Uint8List.fromList(
  List<int>.generate(32, (index) => 255 - index),
);

PeerRecord _peer() => PeerRecord(
  remoteEpk: 'peer',
  sessionName: 'Pi',
  relayUrl: 'wss://relay',
  pairedAt: '2026-07-23T00:00:00Z',
  channel: OwnerChannelState(
    sendKey: base64.encode(_sendKey),
    receiveKey: base64.encode(_receiveKey),
  ),
);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  test('seals outbound and opens authenticated inbound messages', () async {
    final transport = _QueueTransport();
    final storage = _ChannelStorage();
    final channel = SecurePeerChannel(
      transport: transport,
      storage: storage,
      peer: _peer(),
    );

    await channel.send(const Ping(id: 'ping-1'));
    expect(transport.sent, hasLength(1));
    final outbound = await openOwnerChannelFrame(
      key: _sendKey,
      frame: transport.sent.single,
      lastSequence: 0,
    );
    expect(outbound?.sequence, 1);
    expect(jsonDecode(outbound!.json), <String, dynamic>{
      'type': 'ping',
      'id': 'ping-1',
    });
    expect(storage.states.last.sendSequence, 1);

    final messageFuture = channel.serverMessages.first;
    transport.push(
      await sealOwnerChannelFrame(
        key: _receiveKey,
        sequence: 1,
        json: jsonEncode(<String, dynamic>{
          'type': 'pong',
          'in_reply_to': 'ping-1',
        }),
      ),
    );
    final message = await messageFuture;
    expect(message, isA<Pong>());
    expect((message as Pong).inReplyTo, 'ping-1');
    expect(storage.states.last.receiveSequence, 1);
    await channel.close();
  });

  test('drops and audits plaintext after key establishment', () async {
    final transport = _QueueTransport();
    final log = _RecordingDebugLog();
    final channel = SecurePeerChannel(
      transport: transport,
      storage: _ChannelStorage(),
      peer: _peer(),
      debugLog: log,
    );
    final subscription = channel.serverMessages.listen((_) {});

    transport.push(utf8.encode('{"type":"pong","in_reply_to":"x"}'));
    await _settle();

    expect(
      log.events.whereType<PeerFrameEvent>().single.kind,
      'plaintext_post_key',
    );
    expect(transport.closed, isFalse);
    await subscription.cancel();
    await channel.close();
  });

  test('five consecutive authentication failures detach the channel', () async {
    final transport = _QueueTransport();
    final log = _RecordingDebugLog();
    final channel = SecurePeerChannel(
      transport: transport,
      storage: _ChannelStorage(),
      peer: _peer(),
      debugLog: log,
    );
    final subscription = channel.serverMessages.listen((_) {});

    for (var i = 0; i < 5; i++) {
      transport.push(<int>[0x01, ...List<int>.filled(48, i)]);
      await _settle();
    }

    expect(transport.closed, isTrue);
    expect(log.events.whereType<PeerFrameEvent>(), hasLength(5));
    await subscription.cancel();
  });
}

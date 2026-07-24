import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/secure_channel.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/codec.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

class _QueueTransport implements PeerTransport, PeerTransportCloseSignal {
  final _inbound = <Uint8List>[];
  final _waiters = <Completer<Uint8List>>[];
  final List<Uint8List> sent = <Uint8List>[];
  final _closedCompleter = Completer<void>();
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
  Future<void> close() => remoteClose();

  Future<void> remoteClose() async {
    if (closed) return;
    closed = true;
    if (!_closedCompleter.isCompleted) _closedCompleter.complete();
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('transport closed'));
      }
    }
    _waiters.clear();
  }

  @override
  Future<void> get transportClosed => _closedCompleter.future;
}

class _ChannelStorage extends PairingStorage {
  final List<OwnerChannelState> states = <OwnerChannelState>[];
  Completer<void>? _saveBlocker;
  Completer<void>? _saveStarted;

  ({Completer<void> started, Completer<void> unblock}) blockNextSave() {
    final started = Completer<void>();
    final unblock = Completer<void>();
    _saveStarted = started;
    _saveBlocker = unblock;
    return (started: started, unblock: unblock);
  }

  @override
  Future<void> saveChannelState(
    String remoteEpk,
    OwnerChannelState channel,
  ) async {
    states.add(channel);
    final started = _saveStarted;
    final blocker = _saveBlocker;
    _saveStarted = null;
    _saveBlocker = null;
    if (started != null && !started.isCompleted) started.complete();
    if (blocker != null) await blocker.future;
  }
}

class _RecordingDebugLog implements DebugLog {
  final List<DebugEvent> events = <DebugEvent>[];
  final List<({int count, Completer<void> completer})> _countWaiters = [];

  Future<void> untilCount(int count) {
    if (events.length >= count) return Future<void>.value();
    final completer = Completer<void>();
    _countWaiters.add((count: count, completer: completer));
    return completer.future;
  }

  @override
  void log(DebugEvent event) {
    events.add(event);
    for (final waiter in _countWaiters.toList()) {
      if (events.length >= waiter.count) {
        waiter.completer.complete();
        _countWaiters.remove(waiter);
      }
    }
  }

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
    await log.untilCount(1);

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
      await log.untilCount(i + 1);
    }

    expect(transport.closed, isTrue);
    expect(log.events.whereType<PeerFrameEvent>(), hasLength(5));
    await subscription.cancel();
  });

  test(
    'bounds outbound persistence work before allocating continuations',
    () async {
      final transport = _QueueTransport();
      final storage = _ChannelStorage();
      final log = _RecordingDebugLog();
      final blocked = storage.blockNextSave();
      final acceptedMessages = List<ClientMessage>.generate(
        3,
        (index) => Ping(id: 'ping-$index'),
      );
      final acceptedBytes = acceptedMessages.fold<int>(
        0,
        (total, message) =>
            total + utf8.encode(encodeClient(message).trimRight()).length,
      );
      final channel = SecurePeerChannel(
        transport: transport,
        storage: storage,
        peer: _peer(),
        debugLog: log,
        maxPendingOutboundFrames: 10,
        maxPendingOutboundBytes: acceptedBytes,
      );

      final accepted = acceptedMessages.map(channel.send).toList();
      await blocked.started.future;
      expect(channel.debugPendingOutboundFrames, 3);
      expect(channel.debugPendingOutboundBytes, acceptedBytes);

      final overflow = channel.send(const Ping(id: 'overflow-secret'));
      await expectLater(
        overflow,
        throwsA(
          isA<PeerChannelError>().having(
            (error) => error.message,
            'message',
            'owner-channel outbound queue overflow',
          ),
        ),
      );
      expect(transport.closed, isTrue);
      final event = log.events.whereType<PeerFrameEvent>().single;
      expect(event.kind, 'outbound_overflow');
      expect(event.toJson().toString(), isNot(contains('overflow-secret')));
      expect(channel.debugPendingOutboundFrames, 3);

      blocked.unblock.complete();
      await Future.wait(
        accepted.map((future) => future.catchError((Object _) {})),
      );
      await channel.debugWhenOutboundIdle();
      expect(channel.debugPendingOutboundFrames, 0);
      expect(channel.debugPendingOutboundBytes, 0);
    },
  );

  test('outbound frame cap closes a persistence-blocked channel', () async {
    final transport = _QueueTransport();
    final storage = _ChannelStorage();
    final blocked = storage.blockNextSave();
    final channel = SecurePeerChannel(
      transport: transport,
      storage: storage,
      peer: _peer(),
      maxPendingOutboundFrames: 2,
      maxPendingOutboundBytes: 1024,
    );

    final accepted = <Future<void>>[
      channel.send(const Ping(id: 'ping-0')),
      channel.send(const Ping(id: 'ping-1')),
    ];
    await blocked.started.future;
    final overflow = channel.send(const Ping(id: 'ping-2'));
    await expectLater(overflow, throwsA(isA<PeerChannelError>()));
    expect(channel.debugPendingOutboundFrames, 2);
    expect(transport.closed, isTrue);

    blocked.unblock.complete();
    await Future.wait(
      accepted.map((future) => future.catchError((Object _) {})),
    );
    await channel.debugWhenOutboundIdle();
  });

  test(
    'accepted outbound sends preserve sequence order after persistence unblocks',
    () async {
      final transport = _QueueTransport();
      final storage = _ChannelStorage();
      final blocked = storage.blockNextSave();
      final channel = SecurePeerChannel(
        transport: transport,
        storage: storage,
        peer: _peer(),
        maxPendingOutboundFrames: 3,
        maxPendingOutboundBytes: 1024,
      );

      final sends = List<Future<void>>.generate(
        3,
        (index) => channel.send(Ping(id: 'ping-$index')),
      );
      await blocked.started.future;
      expect(transport.sent, isEmpty);
      blocked.unblock.complete();
      await Future.wait(sends);
      await channel.debugWhenOutboundIdle();

      expect(transport.sent, hasLength(3));
      var lastSequence = 0;
      for (var index = 0; index < transport.sent.length; index++) {
        final opened = await openOwnerChannelFrame(
          key: _sendKey,
          frame: transport.sent[index],
          lastSequence: lastSequence,
        );
        expect(opened?.sequence, index + 1);
        expect(jsonDecode(opened!.json)['id'], 'ping-$index');
        lastSequence = opened.sequence;
      }
      expect(storage.states.map((state) => state.sendSequence), [1, 2, 3]);
      await channel.close();
    },
  );

  test(
    'observes transport closure while inbound persistence is blocked',
    () async {
      final transport = _QueueTransport();
      final storage = _ChannelStorage();
      final blocked = storage.blockNextSave();
      final channel = SecurePeerChannel(
        transport: transport,
        storage: storage,
        peer: _peer(),
      );
      final streamClosed = Completer<void>();
      final subscription = channel.serverMessages.listen(
        (_) {},
        onDone: streamClosed.complete,
      );

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
      await blocked.started.future;
      await transport.remoteClose();
      await streamClosed.future;
      expect(blocked.unblock.isCompleted, isFalse);

      blocked.unblock.complete();
      await subscription.cancel();
    },
  );
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:app/data/transport/ws_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bounds buffered data frames and counts drop-new overflow', () async {
    final droppedBytes = <int>[];
    final queue = WsInboundMessageQueue(
      maxFrames: 2,
      maxBytes: 5,
      onOverflow: droppedBytes.add,
    );
    final activeReceive = queue.next();
    final active = Uint8List.fromList(<int>[9]);

    expect(queue.add(active), isTrue);
    expect(await activeReceive, active);

    final first = Uint8List.fromList(<int>[1, 2]);
    final second = Uint8List.fromList(<int>[3, 4, 5]);
    expect(queue.add(first), isTrue);
    expect(queue.add(second), isTrue);
    expect(queue.pendingFrames, 2);
    expect(queue.pendingBytes, 5);

    expect(queue.add(Uint8List.fromList(<int>[6])), isFalse);
    expect(queue.add(Uint8List.fromList(<int>[7, 8])), isFalse);
    expect(droppedBytes, <int>[1, 2]);
    expect(queue.pendingFrames, 2);
    expect(queue.pendingBytes, 5);
    expect(await queue.next(), first);
    expect(await queue.next(), second);
  });

  test('rejects a new frame that would exceed the byte cap', () {
    final queue = WsInboundMessageQueue(maxFrames: 3, maxBytes: 4);
    expect(queue.add(Uint8List.fromList(<int>[1, 2, 3])), isTrue);

    expect(queue.add(Uint8List.fromList(<int>[4, 5])), isFalse);
    expect(queue.pendingFrames, 1);
    expect(queue.pendingBytes, 3);
  });

  test('control classification bypasses a full data queue', () {
    final queue = WsInboundMessageQueue(maxFrames: 1, maxBytes: 1);
    expect(queue.add(Uint8List.fromList(<int>[1])), isTrue);

    final decision = demuxPostAuthInboundFrame(
      raw: jsonEncode(<String, Object>{
        'type': 'peer_online',
        'peer': 'peer-a',
      }),
      activeRoom: 'active-room',
    );

    expect(decision.kind, WsInboundFrameKind.control);
    expect(queue.pendingFrames, 1);
  });

  test(
    'cleanup closes the socket after subscription cancellation fails',
    () async {
      var socketClosed = false;

      await expectLater(
        settleWsCleanupForTesting([
          () async => throw StateError('subscription cleanup failed'),
          () async => socketClosed = true,
        ]),
        throwsA(isA<StateError>()),
      );

      expect(socketClosed, isTrue);
    },
  );

  test('transport close preempts and releases buffered data', () async {
    final queue = WsInboundMessageQueue(maxFrames: 2, maxBytes: 8);
    expect(queue.add(Uint8List.fromList(<int>[1, 2, 3])), isTrue);
    expect(queue.pendingFrames, 1);

    queue.close();

    expect(queue.pendingFrames, 0);
    expect(queue.pendingBytes, 0);
    await expectLater(queue.next(), throwsA(isA<WsTransportError>()));
  });
}

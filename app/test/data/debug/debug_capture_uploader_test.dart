import 'dart:async';
import 'dart:convert';

import 'package:app/data/debug/debug_capture_uploader.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/debug_capture_upload.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeDebugLog implements DebugLog {
  _FakeDebugLog(this.value);
  String? value;

  @override
  Future<String?> export() async => value;
  @override
  Future<void> clear() async {}
  @override
  void log(DebugEvent event) {}
  @override
  void dispose() {}
}

final class _UploadChannel implements IChannel {
  final _messages = StreamController<ServerMessage>.broadcast();
  final sent = <ClientMessage>[];
  int? failChunkSequence;
  bool failedOnce = false;

  @override
  Stream<ServerMessage> get serverMessages => _messages.stream;

  @override
  Future<void> send(ClientMessage message) async {
    sent.add(message);
    switch (message) {
      case CaptureUploadBegin(:final id, :final sessionId, :final uploadId):
        scheduleMicrotask(
          () => _messages.add(
            CaptureUploadAck(
              sessionId: sessionId,
              inReplyTo: id,
              uploadId: uploadId,
              stage: 'begin',
              nextSequence: 0,
            ),
          ),
        );
      case CaptureUploadChunk(
        :final id,
        :final sessionId,
        :final uploadId,
        :final sequence,
      ):
        if (sequence == failChunkSequence && !failedOnce) {
          failedOnce = true;
          scheduleMicrotask(
            () => _messages.add(
              CaptureUploadError(
                sessionId: sessionId,
                inReplyTo: id,
                uploadId: uploadId,
                code: 'io_error',
                message: 'temporary write failure',
              ),
            ),
          );
        } else {
          scheduleMicrotask(
            () => _messages.add(
              CaptureUploadAck(
                sessionId: sessionId,
                inReplyTo: id,
                uploadId: uploadId,
                stage: 'chunk',
                nextSequence: sequence + 1,
              ),
            ),
          );
        }
      case CaptureUploadEnd(:final id, :final sessionId, :final uploadId):
        scheduleMicrotask(
          () => _messages.add(
            CaptureUploadAck(
              sessionId: sessionId,
              inReplyTo: id,
              uploadId: uploadId,
              stage: 'delivered',
              path: 'debug/app-capture-test.bin',
              bytes: sent.whereType<CaptureUploadChunk>().fold<int>(
                0,
                (sum, chunk) => sum + base64Decode(chunk.payload).length,
              ),
              events: 2,
            ),
          ),
        );
      default:
        throw StateError('unexpected message ${message.type}');
    }
  }

  @override
  Future<void> close() => _messages.close();
}

const _peer = PeerRecord(
  remoteEpk: 'capture-peer',
  sessionName: 'Pi',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
  roomId: 'main',
);

Future<({ConnectionManager connection, _UploadChannel channel})>
_online() async {
  final channel = _UploadChannel();
  final connection = ConnectionManager(
    factory: (_, _) async => channel,
    storage: PairingStorage(),
    emitDebounce: Duration.zero,
  );
  connection.adopt(channel, _peer);
  channel._messages.add(
    const PairOk(
      inReplyTo: 'pair',
      sessionName: 'Pi',
      sessionStartedAt: 1,
      sessionId: 'capture-session',
      roomId: 'main',
    ),
  );
  await Future<void>.delayed(Duration.zero);
  return (connection: connection, channel: channel);
}

void main() {
  test(
    'chunks at 8 KiB, sequences from zero, reports progress, and returns path',
    () async {
      final online = await _online();
      addTearDown(() async {
        await online.connection.disconnect();
        online.connection.dispose();
      });
      final body = List.filled(900, '{"tag":"capture"}').join('\n');
      final uploader = DebugCaptureUploaderImpl(
        _FakeDebugLog(body),
        online.connection,
        deviceLabel: () => 'Test Android',
      );
      final progress = <DebugCaptureUploadProgress>[];

      final result = await uploader.uploadLatest(onProgress: progress.add);

      final begin = online.channel.sent.whereType<CaptureUploadBegin>().single;
      final chunks = online.channel.sent
          .whereType<CaptureUploadChunk>()
          .toList();
      expect(begin.deviceLabel, 'Test Android');
      expect(chunks.length, greaterThan(1));
      expect(
        chunks.map((chunk) => chunk.sequence),
        orderedEquals(List.generate(chunks.length, (i) => i)),
      );
      expect(
        chunks.every(
          (chunk) =>
              base64Decode(chunk.payload).length <= captureUploadMaxChunkBytes,
        ),
        isTrue,
      );
      expect(progress.first.reading, isTrue);
      expect(progress.last.fraction, 1);
      expect(result.path, 'debug/app-capture-test.bin');
    },
  );

  test(
    'mid-chunk typed failure retries from a fresh begin and sequence zero',
    () async {
      final online = await _online();
      addTearDown(() async {
        await online.connection.disconnect();
        online.connection.dispose();
      });
      online.channel.failChunkSequence = 1;
      final uploader = DebugCaptureUploaderImpl(
        _FakeDebugLog(List.filled(900, '{"tag":"capture"}').join('\n')),
        online.connection,
      );

      await expectLater(
        uploader.uploadLatest(),
        throwsA(isA<DebugCaptureUploadFailure>()),
      );
      final firstUpload = online.channel.sent
          .whereType<CaptureUploadBegin>()
          .single
          .uploadId;
      final result = await uploader.uploadLatest();
      final begins = online.channel.sent
          .whereType<CaptureUploadBegin>()
          .toList();
      expect(begins, hasLength(2));
      expect(begins.last.uploadId, isNot(firstUpload));
      final retryChunks = online.channel.sent
          .whereType<CaptureUploadChunk>()
          .where((chunk) => chunk.uploadId == begins.last.uploadId)
          .toList();
      expect(retryChunks.first.sequence, 0);
      expect(result.path, isNotEmpty);
    },
  );

  test('oversize capture is refused before any transport message', () async {
    final online = await _online();
    addTearDown(() async {
      await online.connection.disconnect();
      online.connection.dispose();
    });
    final uploader = DebugCaptureUploaderImpl(
      _FakeDebugLog(List.filled(captureUploadMaxTotalBytes + 1, 'x').join()),
      online.connection,
    );

    await expectLater(
      uploader.uploadLatest(),
      throwsA(
        isA<DebugCaptureUploadFailure>().having(
          (error) => error.code,
          'code',
          'too_large',
        ),
      ),
    );
    expect(online.channel.sent, isEmpty);
  });
}

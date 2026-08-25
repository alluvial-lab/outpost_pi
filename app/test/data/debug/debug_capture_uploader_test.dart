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
  _UploadChannel({this.onSend});

  final _messages = StreamController<ServerMessage>.broadcast();
  final sent = <ClientMessage>[];
  final FutureOr<void> Function(_UploadChannel channel, ClientMessage message)?
  onSend;
  int? failChunkSequence;
  bool failedOnce = false;

  @override
  Stream<ServerMessage> get serverMessages => _messages.stream;

  @override
  Future<void> send(ClientMessage message) async {
    sent.add(message);
    final scripted = onSend;
    if (scripted != null) {
      await scripted(this, message);
      return;
    }
    respondSuccess(message);
  }

  void respondSuccess(ClientMessage message) {
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

  void respondError(ClientMessage message, String code) {
    final (id, sessionId, uploadId) = switch (message) {
      CaptureUploadBegin(:final id, :final sessionId, :final uploadId) => (
        id,
        sessionId,
        uploadId,
      ),
      CaptureUploadChunk(:final id, :final sessionId, :final uploadId) => (
        id,
        sessionId,
        uploadId,
      ),
      CaptureUploadEnd(:final id, :final sessionId, :final uploadId) => (
        id,
        sessionId,
        uploadId,
      ),
      _ => throw StateError('unexpected message ${message.type}'),
    };
    scheduleMicrotask(
      () => _messages.add(
        CaptureUploadError(
          sessionId: sessionId,
          inReplyTo: id,
          uploadId: uploadId,
          code: code,
          message: 'injected $code',
        ),
      ),
    );
  }

  Future<void> closeInbound() => _messages.close();

  void errorInbound() => _messages.addError(StateError('channel dropped'));

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

Future<({ConnectionManager connection, _UploadChannel channel})> _online({
  _UploadChannel? withChannel,
  String sessionId = 'capture-session',
}) async {
  final channel = withChannel ?? _UploadChannel();
  final connection = ConnectionManager(
    factory: (_, _) async => channel,
    storage: PairingStorage(),
    emitDebounce: Duration.zero,
  );
  connection.adopt(channel, _peer);
  channel._messages.add(
    PairOk(
      inReplyTo: 'pair',
      sessionName: 'Pi',
      sessionStartedAt: 1,
      sessionId: sessionId,
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

      final firstProgress = <DebugCaptureUploadProgress>[];
      await expectLater(
        uploader.uploadLatest(onProgress: firstProgress.add),
        throwsA(
          isA<DebugCaptureUploadFailure>().having(
            (failure) => failure.code,
            'code',
            'io_error',
          ),
        ),
      );
      final firstBegin = online.channel.sent
          .whereType<CaptureUploadBegin>()
          .single;
      final firstUpload = firstBegin.uploadId;
      expect(online.channel.sent.whereType<CaptureUploadEnd>(), isEmpty);
      expect(firstProgress.last.fraction, lessThan(1));
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

  test('server busy is surfaced before any chunk is sent', () async {
    final busy = _UploadChannel(
      onSend: (channel, message) {
        if (message is CaptureUploadBegin) {
          channel.respondError(message, 'busy');
        } else {
          channel.respondSuccess(message);
        }
      },
    );
    final online = await _online(withChannel: busy);
    addTearDown(() async {
      await online.connection.disconnect();
      online.connection.dispose();
    });
    final uploader = DebugCaptureUploaderImpl(
      _FakeDebugLog('{"tag":"capture"}'),
      online.connection,
    );

    await expectLater(
      uploader.uploadLatest(),
      throwsA(
        isA<DebugCaptureUploadFailure>().having(
          (failure) => failure.code,
          'code',
          'busy',
        ),
      ),
    );
    expect(busy.sent, hasLength(1));
    expect(busy.sent.single, isA<CaptureUploadBegin>());
  });

  test(
    'checksum rejection preserves the server code and never delivers',
    () async {
      final rejecting = _UploadChannel(
        onSend: (channel, message) {
          if (message is CaptureUploadEnd) {
            channel.respondError(message, 'checksum_mismatch');
          } else {
            channel.respondSuccess(message);
          }
        },
      );
      final online = await _online(withChannel: rejecting);
      addTearDown(() async {
        await online.connection.disconnect();
        online.connection.dispose();
      });
      final uploader = DebugCaptureUploaderImpl(
        _FakeDebugLog('{"tag":"capture"}'),
        online.connection,
      );

      await expectLater(
        uploader.uploadLatest(),
        throwsA(
          isA<DebugCaptureUploadFailure>().having(
            (failure) => failure.code,
            'code',
            'checksum_mismatch',
          ),
        ),
      );
      expect(rejecting.sent.whereType<CaptureUploadEnd>(), hasLength(1));
    },
  );

  test(
    'channel drop mid-upload retries on the replacement from begin and sequence zero',
    () async {
      final dropped = _UploadChannel(
        onSend: (channel, message) async {
          if (message case CaptureUploadChunk(sequence: 1)) {
            await channel.closeInbound();
          } else {
            channel.respondSuccess(message);
          }
        },
      );
      final online = await _online(withChannel: dropped);
      addTearDown(() async {
        await online.connection.disconnect();
        online.connection.dispose();
      });
      final uploader = DebugCaptureUploaderImpl(
        _FakeDebugLog(List.filled(900, '{"tag":"capture"}').join('\n')),
        online.connection,
      );

      await expectLater(
        uploader.uploadLatest(),
        throwsA(
          isA<DebugCaptureUploadFailure>().having(
            (failure) => failure.code,
            'code',
            'disconnected',
          ),
        ),
      );
      final abandoned = dropped.sent.whereType<CaptureUploadBegin>().single;
      expect(dropped.sent.whereType<CaptureUploadEnd>(), isEmpty);

      final replacement = _UploadChannel();
      online.connection.adopt(replacement, _peer);
      replacement._messages.add(
        const PairOk(
          inReplyTo: 'replacement-pair',
          sessionName: 'Pi',
          sessionStartedAt: 2,
          sessionId: 'replacement-session',
          roomId: 'main',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final result = await uploader.uploadLatest();
      final replacementBegin = replacement.sent
          .whereType<CaptureUploadBegin>()
          .single;
      final replacementChunks = replacement.sent
          .whereType<CaptureUploadChunk>()
          .toList();
      expect(replacementBegin.uploadId, isNot(abandoned.uploadId));
      expect(replacementBegin.sessionId, 'replacement-session');
      expect(replacementChunks.first.sequence, 0);
      expect(result.path, isNotEmpty);
    },
  );

  test(
    'send, stream-error, and deadline failures have stable typed codes',
    () async {
      Future<void> expectCode(
        _UploadChannel channel,
        String code, {
        Duration timeout = const Duration(seconds: 1),
      }) async {
        final online = await _online(withChannel: channel);
        try {
          final uploader = DebugCaptureUploaderImpl(
            _FakeDebugLog('{"tag":"capture"}'),
            online.connection,
            replyTimeout: timeout,
          );
          await expectLater(
            uploader.uploadLatest(),
            throwsA(
              isA<DebugCaptureUploadFailure>().having(
                (failure) => failure.code,
                'code',
                code,
              ),
            ),
          );
        } finally {
          await online.connection.disconnect();
          online.connection.dispose();
        }
      }

      await expectCode(
        _UploadChannel(onSend: (_, _) => throw StateError('send failed')),
        'send_failed',
      );
      await expectCode(
        _UploadChannel(
          onSend: (channel, _) => scheduleMicrotask(channel.errorInbound),
        ),
        'disconnected',
      );
      await expectCode(
        _UploadChannel(onSend: (_, _) {}),
        'timeout',
        timeout: const Duration(milliseconds: 5),
      );
    },
  );

  test(
    'malformed correlated acknowledgements fail while unrelated ones are ignored',
    () async {
      final wrongStage = _UploadChannel(
        onSend: (channel, message) {
          if (message case CaptureUploadBegin(
            :final id,
            :final sessionId,
            :final uploadId,
          )) {
            channel._messages.add(
              CaptureUploadAck(
                sessionId: sessionId,
                inReplyTo: id,
                uploadId: uploadId,
                stage: 'chunk',
              ),
            );
          }
        },
      );
      final wrongStageOnline = await _online(withChannel: wrongStage);
      final wrongStageUploader = DebugCaptureUploaderImpl(
        _FakeDebugLog('{"tag":"capture"}'),
        wrongStageOnline.connection,
      );
      await expectLater(
        wrongStageUploader.uploadLatest(),
        throwsA(
          isA<DebugCaptureUploadFailure>().having(
            (failure) => failure.code,
            'code',
            'bad_sequence',
          ),
        ),
      );
      await wrongStageOnline.connection.disconnect();
      wrongStageOnline.connection.dispose();

      final wrongSequence = _UploadChannel(
        onSend: (channel, message) {
          if (message case CaptureUploadChunk(
            :final id,
            :final sessionId,
            :final uploadId,
            :final sequence,
          )) {
            channel._messages.add(
              CaptureUploadAck(
                sessionId: sessionId,
                inReplyTo: id,
                uploadId: uploadId,
                stage: 'chunk',
                nextSequence: sequence + 2,
              ),
            );
          } else {
            channel.respondSuccess(message);
          }
        },
      );
      final wrongSequenceOnline = await _online(withChannel: wrongSequence);
      final wrongSequenceUploader = DebugCaptureUploaderImpl(
        _FakeDebugLog('{"tag":"capture"}'),
        wrongSequenceOnline.connection,
      );
      await expectLater(
        wrongSequenceUploader.uploadLatest(),
        throwsA(
          isA<DebugCaptureUploadFailure>().having(
            (failure) => failure.code,
            'code',
            'bad_sequence',
          ),
        ),
      );
      expect(wrongSequence.sent.whereType<CaptureUploadEnd>(), isEmpty);
      await wrongSequenceOnline.connection.disconnect();
      wrongSequenceOnline.connection.dispose();

      final noPath = _UploadChannel(
        onSend: (channel, message) {
          if (message case CaptureUploadEnd(
            :final id,
            :final sessionId,
            :final uploadId,
          )) {
            channel._messages.add(
              CaptureUploadAck(
                sessionId: sessionId,
                inReplyTo: id,
                uploadId: uploadId,
                stage: 'delivered',
              ),
            );
          } else {
            channel.respondSuccess(message);
          }
        },
      );
      final noPathOnline = await _online(withChannel: noPath);
      final noPathUploader = DebugCaptureUploaderImpl(
        _FakeDebugLog('{"tag":"capture"}'),
        noPathOnline.connection,
      );
      await expectLater(
        noPathUploader.uploadLatest(),
        throwsA(
          isA<DebugCaptureUploadFailure>().having(
            (failure) => failure.code,
            'code',
            'io_error',
          ),
        ),
      );
      await noPathOnline.connection.disconnect();
      noPathOnline.connection.dispose();

      final unrelated = _UploadChannel(
        onSend: (channel, message) {
          if (message case CaptureUploadBegin(:final sessionId)) {
            channel._messages.add(
              CaptureUploadAck(
                sessionId: sessionId,
                inReplyTo: 'another-request',
                uploadId: 'another-upload',
                stage: 'begin',
              ),
            );
          }
          channel.respondSuccess(message);
        },
      );
      final unrelatedOnline = await _online(withChannel: unrelated);
      final unrelatedUploader = DebugCaptureUploaderImpl(
        _FakeDebugLog('{"tag":"capture"}'),
        unrelatedOnline.connection,
      );
      expect((await unrelatedUploader.uploadLatest()).path, isNotEmpty);
      await unrelatedOnline.connection.disconnect();
      unrelatedOnline.connection.dispose();
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

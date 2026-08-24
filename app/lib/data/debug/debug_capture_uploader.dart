import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/debug_capture_upload.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/protocol/uuid7.dart';
import 'package:cryptography/cryptography.dart';

/// Stream debug-log snapshots over the currently active protected owner channel.
final class DebugCaptureUploaderImpl implements DebugCaptureUploader {
  DebugCaptureUploaderImpl(
    this._debugLog,
    this._connection, {
    String Function()? deviceLabel,
    Duration replyTimeout = const Duration(seconds: 15),
  }) : _deviceLabel = deviceLabel ?? _defaultDeviceLabel,
       _replyTimeout = replyTimeout;

  final DebugLog _debugLog;
  final ConnectionManager _connection;
  final String Function() _deviceLabel;
  final Duration _replyTimeout;

  @override
  Future<DebugCaptureUploadResult> uploadLatest({
    void Function(DebugCaptureUploadProgress progress)? onProgress,
  }) async {
    onProgress?.call(const DebugCaptureUploadProgress.reading());
    final capture = await _debugLog.export();
    if (capture == null || capture.trim().isEmpty) {
      throw const DebugCaptureUploadFailure(
        'empty_capture',
        'No debug logs are available yet.',
      );
    }
    final bytes = utf8.encode(capture.endsWith('\n') ? capture : '$capture\n');
    if (bytes.length > captureUploadMaxTotalBytes) {
      throw const DebugCaptureUploadFailure(
        'too_large',
        'Debug logs exceed the 2 MiB delivery limit. Clear the log and retry.',
      );
    }

    final channel = _connection.channel;
    if (channel == null) {
      throw const DebugCaptureUploadFailure(
        'offline',
        'Pi is offline. Reconnect and retry.',
      );
    }
    final sessionId = _connection.activeSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      throw const DebugCaptureUploadFailure(
        'session_unavailable',
        'Pi session identity is unavailable. Reconnect and retry.',
      );
    }

    final uploadId = 'capture_${uuid7()}';
    await _sendAndWait(
      channel,
      CaptureUploadBegin(
        id: 'capture_begin_${uuid7()}',
        sessionId: sessionId,
        uploadId: uploadId,
        deviceLabel: _deviceLabel(),
        totalBytes: bytes.length,
        captureKind: 'debug_log_jsonl',
      ),
      uploadId,
      expectedStage: 'begin',
    );

    var sent = 0;
    var sequence = 0;
    onProgress?.call(
      DebugCaptureUploadProgress.sending(
        bytesSent: 0,
        totalBytes: bytes.length,
      ),
    );
    while (sent < bytes.length) {
      final end = math.min(sent + captureUploadMaxChunkBytes, bytes.length);
      final chunk = bytes.sublist(sent, end);
      final ack = await _sendAndWait(
        channel,
        CaptureUploadChunk(
          id: 'capture_chunk_${uuid7()}',
          sessionId: sessionId,
          uploadId: uploadId,
          sequence: sequence,
          payload: base64Encode(chunk),
        ),
        uploadId,
        expectedStage: 'chunk',
      );
      if (ack.nextSequence != sequence + 1) {
        throw const DebugCaptureUploadFailure(
          'bad_sequence',
          'Pi acknowledged an unexpected capture sequence. Retry from the start.',
        );
      }
      sent = end;
      sequence++;
      onProgress?.call(
        DebugCaptureUploadProgress.sending(
          bytesSent: sent,
          totalBytes: bytes.length,
        ),
      );
    }

    final digest = await Sha256().hash(bytes);
    final checksum = digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final delivered = await _sendAndWait(
      channel,
      CaptureUploadEnd(
        id: 'capture_end_${uuid7()}',
        sessionId: sessionId,
        uploadId: uploadId,
        sha256: checksum,
      ),
      uploadId,
      expectedStage: 'delivered',
    );
    final path = delivered.path;
    if (path == null || path.isEmpty) {
      throw const DebugCaptureUploadFailure(
        'io_error',
        'Pi did not return the delivered file path. Retry from the start.',
      );
    }
    return DebugCaptureUploadResult(
      path: path,
      bytes: delivered.bytes ?? bytes.length,
      events: delivered.events ?? const LineSplitter().convert(capture).length,
    );
  }

  Future<CaptureUploadAck> _sendAndWait(
    IChannel channel,
    ClientMessage message,
    String targetUploadId, {
    required String expectedStage,
  }) async {
    final requestId = switch (message) {
      CaptureUploadBegin(:final id) => id,
      CaptureUploadChunk(:final id) => id,
      CaptureUploadEnd(:final id) => id,
      _ => throw StateError('capture uploader received a non-capture message'),
    };
    final completer = Completer<CaptureUploadAck>();
    late final StreamSubscription<ServerMessage> subscription;
    subscription = channel.serverMessages.listen(
      (reply) {
        switch (reply) {
          case CaptureUploadAck(:final inReplyTo, :final uploadId, :final stage)
              when inReplyTo == requestId && uploadId == targetUploadId:
            if (stage != expectedStage) {
              if (!completer.isCompleted) {
                completer.completeError(
                  const DebugCaptureUploadFailure(
                    'bad_sequence',
                    'Pi returned an unexpected upload acknowledgement.',
                  ),
                );
              }
            } else if (!completer.isCompleted) {
              completer.complete(reply);
            }
          case CaptureUploadError(
                :final inReplyTo,
                uploadId: final replyUploadId,
                :final code,
                :final message,
              )
              when inReplyTo == requestId && replyUploadId == targetUploadId:
            if (!completer.isCompleted) {
              completer.completeError(DebugCaptureUploadFailure(code, message));
            }
          default:
            break;
        }
      },
      onError: (Object _) {
        if (!completer.isCompleted) {
          completer.completeError(
            const DebugCaptureUploadFailure(
              'disconnected',
              'Connection lost. Retry from the start.',
            ),
          );
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            const DebugCaptureUploadFailure(
              'disconnected',
              'Connection lost. Retry from the start.',
            ),
          );
        }
      },
    );
    try {
      await channel.send(message);
      return await completer.future.timeout(
        _replyTimeout,
        onTimeout: () => throw const DebugCaptureUploadFailure(
          'timeout',
          'Pi did not acknowledge the capture. Retry from the start.',
        ),
      );
    } on DebugCaptureUploadFailure {
      rethrow;
    } catch (_) {
      throw const DebugCaptureUploadFailure(
        'send_failed',
        'Capture could not be sent. Retry from the start.',
      );
    } finally {
      await subscription.cancel();
    }
  }

  static String _defaultDeviceLabel() {
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isAndroid) return 'Android device';
    return 'Outpost-Pi app';
  }
}

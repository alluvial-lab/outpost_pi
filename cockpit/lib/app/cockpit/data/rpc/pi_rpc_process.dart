import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/cockpit/data/adapters/rpc_data_mapper.dart';
import 'package:cockpit/app/cockpit/data/adapters/rpc_event_mapper.dart';
import 'package:cockpit/app/core/data/rpc/jsonl_line_splitter.dart';
import 'package:cockpit/app/core/data/setup/outpost_pi_resolver.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_process_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_snapshot.dart';
import 'package:cockpit/app/cockpit/domain/entities/context_usage.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/app/cockpit/domain/entities/prompt_image.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_ui_response.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_event.dart';
import 'package:cockpit/app/cockpit/data/rpc/pi_process_registry.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/rpc_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter/foundation.dart';

/// Run an [RpcProcessGateway] over a `dart:io` [Process].
///
/// This adapter owns one `pi --mode rpc` child per instance: spawning it,
/// serializing stdin writes, parsing stdout through [JsonlLineSplitter] and
/// [RpcEventMapper], observing exit, and terminating it during disposal so no
/// child is orphaned. See `docs/rpc-protocol.md` for the RPC contract.
class PiRpcProcess implements RpcProcessGateway {
  PiRpcProcess(this._config);

  final PiSpawnConfig _config;
  final RpcEventMapper _mapper = const RpcEventMapper();
  final RpcDataMapper _dataMapper = const RpcDataMapper();
  final StreamController<RpcEvent> _events =
      StreamController<RpcEvent>.broadcast();

  /// Track pending requests until a `response` with the matching `id` arrives.
  final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};
  int _seq = 0;

  /// Serialize stdin writes to prevent concurrent `write` and `flush` calls.
  ///
  /// Each write waits for its predecessor, avoiding
  /// `Bad state: StreamSink is bound to a stream` when boot and restoration
  /// commands overlap.
  Future<void> _writeChain = Future<void>.value();

  Process? _process;
  String? _cwd;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  @override
  Stream<RpcEvent> get events => _events.stream;

  @override
  bool get isRunning => _process != null;

  @override
  String? get workingDirectory => _cwd;

  @override
  Future<Result<void, RpcError>> spawn({
    required String workingDirectory,
    Map<String, String>? environment,
    String? sessionId,
  }) async {
    if (_process != null) {
      return const Failure(
        RpcError('An agent is already running in this session.'),
      );
    }
    try {
      // Start from the parent environment with the Node binary on PATH. The
      // `pi` shim uses `#!/usr/bin/env node`, while GUI apps omit nvm/Homebrew.
      final base = await envWithNodeOnPath();
      final env = environment != null ? {...base, ...environment} : base;
      final process = await Process.start(
        _config.executable,
        _config.spawnArgs(sessionId: sessionId),
        workingDirectory: workingDirectory,
        environment: env,
        // On Windows, the npm `.cmd`/`.bat` Pi shim requires a shell.
        runInShell: Platform.isWindows,
      );
      _process = process;
      _cwd = workingDirectory;
      unawaited(PiProcessRegistry.register(process.pid));

      _stdoutSub = process.stdout
          .transform(const JsonlLineSplitter())
          .listen(_onStdoutLine, onError: _onStreamError);

      _stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onStderrLine, onError: _onStreamError);

      // Observe normal exit or crash without blocking spawn.
      unawaited(process.exitCode.then(_onExit));

      return const Success(null);
    } catch (error, stackTrace) {
      _process = null;
      _cwd = null;
      return Failure(
        RpcError(
          'Failed to spawn "${_config.executable}": $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void, RpcError>> sendPrompt(
    String message, {
    bool steerIfBusy = false,
    List<PromptImage> images = const <PromptImage>[],
  }) async {
    final process = _process;
    if (process == null) {
      return const Failure(RpcError('No agent running.'));
    }
    final command = <String, dynamic>{'type': 'prompt', 'message': message};
    if (steerIfBusy) command['streamingBehavior'] = 'steer';
    if (images.isNotEmpty) {
      command['images'] = <Map<String, String>>[
        for (final image in images)
          {'type': 'image', 'data': image.data, 'mimeType': image.mimeType},
      ];
    }
    try {
      await _writeLine('${jsonEncode(command)}\n');
      return const Success(null);
    } catch (error, stackTrace) {
      return Failure(
        RpcError(
          'Failed to send prompt: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void, RpcError>> respondUi(
    String id,
    RpcUiResponse response,
  ) async {
    final process = _process;
    if (process == null) {
      return const Failure(RpcError('No agent running.'));
    }
    final command = _schemaUiResponse(id, response);
    try {
      await _writeLine('${jsonEncode(command)}\n');
      return const Success(null);
    } catch (error, stackTrace) {
      return Failure(
        RpcError(
          'Failed to respond to UI: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<void> kill() async {
    final process = _process;
    if (process == null) return;

    // Closing stdin is the graceful path and lets Pi exit with code 0.
    try {
      await process.stdin.close();
    } catch (_) {
      // stdin may already be closed.
    }

    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
    // _onExit clears references and emits RpcProcessExit.
  }

  @override
  void dispose() {
    // Synchronous shutdown safety net for the injector. [kill] owns the truly
    // graceful path; this fallback guarantees that no process is orphaned.
    final process = _process;
    if (process != null) {
      try {
        process.stdin.close();
      } catch (_) {}
      process.kill(ProcessSignal.sigterm);
    }
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    if (!_events.isClosed) _events.close();
  }

  void _onStdoutLine(String line) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      debugPrint(
        _rpcFrameDiagnostic(
          processOutput: true,
          line: line,
          malformed: true,
          knownRequestIds: _pending.keys.toSet(),
        ),
      );
      _emit(const RpcUnknown('<parse-error>'));
      return;
    }

    debugPrint(
      _rpcFrameDiagnostic(
        processOutput: true,
        line: line,
        decoded: decoded,
        knownRequestIds: _pending.keys.toSet(),
      ),
    );
    if (decoded is! Map<String, dynamic>) {
      _emit(const RpcUnknown('<non-object>'));
      return;
    }
    try {
      // Complete responses correlated by request id without emitting them as
      // events.
      if (decoded['type'] == 'response') {
        final id = decoded['id'];
        if (id is String) {
          final completer = _pending.remove(id);
          if (completer != null) {
            completer.complete(decoded);
            return;
          }
        }
      }
      _emit(_mapper.fromJson(decoded));
    } catch (_) {
      _emit(const RpcUnknown('<parse-error>'));
    }
  }

  /// Write one stdin line in sequence with all other writes.
  ///
  /// Waits for [_writeChain] before touching the sink, preventing concurrent
  /// `write` and `flush` calls from binding the stream twice.
  Future<void> _writeLine(String line) {
    final result = _writeChain.then((_) async {
      final process = _process;
      if (process == null) {
        throw const RpcError('No agent running.');
      }
      debugPrint(rpcFrameDiagnosticForTesting(line, processOutput: false));
      process.stdin.write(line);
      await process.stdin.flush();
    });
    // Keep the chain alive after a failed write without forwarding that error
    // to the next queued writer; the original caller receives it via `result`.
    _writeChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Send a command with an `id` and await its matching `response`.
  ///
  /// Throws [RpcError] on command failure or timeout; public methods convert
  /// that exception to [Result].
  Future<Map<String, dynamic>> _request(Map<String, dynamic> command) async {
    final process = _process;
    if (process == null) {
      throw const RpcError('No agent running.');
    }
    final id = 'req-${++_seq}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    try {
      await _writeLine(
        '${jsonEncode(<String, dynamic>{...command, 'id': id})}\n',
      );
    } catch (error, stackTrace) {
      _pending.remove(id);
      throw RpcError(
        'Failed to send ${command['type']}: $error',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    final response = await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pending.remove(id);
        throw RpcError(
          'Timed out waiting for a response to ${command['type']}.',
        );
      },
    );
    if (response['success'] != true) {
      throw RpcError(
        '${command['type']} failed: ${response['error'] ?? "unknown error"}',
      );
    }
    return response;
  }

  Future<Result<T, RpcError>> _guard<T>(Future<T> Function() body) async {
    try {
      return Success(await body());
    } on RpcError catch (error) {
      return Failure(error);
    } catch (error, stackTrace) {
      return Failure(RpcError('$error', cause: error, stackTrace: stackTrace));
    }
  }

  @override
  Future<Result<List<PiModel>, RpcError>> availableModels() => _guard(() async {
    final response = await _request({'type': 'get_available_models'});
    return _dataMapper.models(response['data']);
  });

  @override
  Future<Result<List<PiCommand>, RpcError>> commands() => _guard(() async {
    final response = await _request({'type': 'get_commands'});
    return _dataMapper.commands(response['data']);
  });

  @override
  Future<Result<AgentSnapshot, RpcError>> state() => _guard(() async {
    final response = await _request({'type': 'get_state'});
    return _dataMapper.state(response['data']);
  });

  @override
  Future<Result<PiModel, RpcError>> setModel(PiModel model) => _guard(() async {
    final response = await _request({
      'type': 'set_model',
      'provider': model.provider,
      'modelId': model.id,
    });
    return _dataMapper.model(response['data']) ?? model;
  });

  @override
  Future<Result<void, RpcError>> setThinkingLevel(ThinkingLevel level) =>
      _guard(() async {
        await _request({'type': 'set_thinking_level', 'level': level.wire});
      });

  @override
  Future<Result<ContextUsage?, RpcError>> sessionStats() => _guard(() async {
    final response = await _request({'type': 'get_session_stats'});
    return _dataMapper.contextUsage(response['data']);
  });

  @override
  Future<Result<void, RpcError>> abort() => _guard(() async {
    await _request({'type': 'abort'});
  });

  @override
  Future<Result<void, RpcError>> newSession() => _guard(() async {
    await _request({'type': 'new_session'});
  });

  @override
  Future<Result<void, RpcError>> compact() => _guard(() async {
    await _request({'type': 'compact'});
  });

  @override
  Future<Result<void, RpcError>> switchSession(String sessionPath) =>
      _guard(() async {
        await _request({'type': 'switch_session', 'sessionPath': sessionPath});
      });

  @override
  Future<Result<List<CockpitTranscriptEvent>, RpcError>> getMessages({
    required String sessionId,
  }) => _guard(() async {
    final response = await _request({'type': 'get_messages'});
    return _dataMapper.transcriptEvents(response['data'], sessionId: sessionId);
  });

  static const _controlEnvelopeType = 'outpost_pi_control';

  @override
  Future<Result<void, RpcError>> sendControl(PiControlCommand command) async {
    if (_process == null) {
      return const Failure(RpcError('No agent running.'));
    }
    try {
      await _writeLine('${jsonEncode(_schemaControlPrompt(command))}\n');
      return const Success(null);
    } catch (error, stackTrace) {
      return Failure(
        RpcError(
          'Failed to send control: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  static Map<String, dynamic> _schemaControlPrompt(PiControlCommand command) =>
      {
        'type': 'prompt',
        'message': jsonEncode(_schemaControlEnvelope(command)),
      };

  static Map<String, Object?> _schemaUiResponse(
    String id,
    RpcUiResponse response,
  ) {
    final payload = switch (response) {
      RpcUiValueResponse(:final value) => <String, Object?>{'value': value},
      RpcUiConfirmationResponse(:final confirmed) => <String, Object?>{
        'confirmed': confirmed,
      },
      RpcUiCancelledResponse() => <String, Object?>{'cancelled': true},
    };
    return <String, Object?>{
      'type': 'extension_ui_response',
      'id': id,
      ...payload,
    };
  }

  static Map<String, dynamic> _schemaControlEnvelope(PiControlCommand command) {
    final envelope = <String, dynamic>{
      'type': _controlEnvelopeType,
      'command': command.command.wire,
    };
    if (command.isRename) {
      final name = command.name;
      if (name == null || name.isEmpty) {
        throw const RpcError('Control rename requires a non-empty name.');
      }
      envelope['name'] = name;
    }
    return envelope;
  }

  void _onStderrLine(String line) {
    if (line.trim().isEmpty) return;
    _emit(const RpcDiagnostic(RpcDiagnosticKind.childStderr));
  }

  void _onStreamError(Object _, StackTrace _) {
    _emit(const RpcDiagnostic(RpcDiagnosticKind.streamReadFailure));
  }

  void _onExit(int code) {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    final pid = _process?.pid;
    _process = null;
    _cwd = null;
    if (pid != null) unawaited(PiProcessRegistry.unregister(pid));
    // Fail every pending request when the process exits.
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(RpcError('Process exited (code=$code).'));
      }
    }
    _pending.clear();
    _emit(RpcProcessExit(code));
  }

  void _emit(RpcEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}

String _rpcFrameDiagnostic({
  required bool processOutput,
  required String line,
  Object? decoded,
  bool malformed = false,
  Set<String>? knownRequestIds,
}) {
  final direction = processOutput ? 'out' : 'in';
  final bytes = utf8.encode(line).length;
  final category = _rpcFrameCategory(decoded, malformed: malformed);
  // Only admit a request id whose PROVENANCE is known (Cockpit generated it
  // and is awaiting its response). A shape-only regex would let an untrusted
  // child smuggle a numeric secret in an event/response id; verifying
  // against `_pending` keys ensures only Cockpit-generated ids survive.
  final requestId = decoded is Map<String, dynamic>
      ? _safeGeneratedRequestId(decoded['id'], knownRequestIds)
      : null;
  return '[rpc-mode-agent][$direction] bytes=$bytes category=$category'
      '${requestId == null ? '' : ' id=$requestId'}';
}

String _rpcFrameCategory(Object? decoded, {required bool malformed}) {
  if (malformed) return 'malformed';
  if (decoded is! Map<String, dynamic>) return 'non_object';
  return decoded['type'] == 'response' ? 'response' : 'event';
}

String? _safeGeneratedRequestId(
  Object? value,
  Set<String>? knownRequestIds,
) {
  if (value is! String || !RegExp(r'^req-[0-9]+$').hasMatch(value)) {
    return null;
  }
  // Provenance check: only Cockpit-generated ids (in `_pending`) survive.
  // An untrusted child can craft a matching shape; only membership proves it
  // was ours.
  if (knownRequestIds == null || !knownRequestIds.contains(value)) {
    return null;
  }
  return value;
}

/// Format an RPC frame diagnostic without retaining or returning its payload.
@visibleForTesting
String rpcFrameDiagnosticForTesting(
  String line, {
  required bool processOutput,
  Set<String>? knownRequestIds,
}) {
  try {
    return _rpcFrameDiagnostic(
      processOutput: processOutput,
      line: line,
      decoded: jsonDecode(line),
      knownRequestIds: knownRequestIds,
    );
  } catch (_) {
    return _rpcFrameDiagnostic(
      processOutput: processOutput,
      line: line,
      malformed: true,
      knownRequestIds: knownRequestIds,
    );
  }
}

@visibleForTesting
Map<String, dynamic> schemaControlPromptForTesting(PiControlCommand command) =>
    PiRpcProcess._schemaControlPrompt(command);

@visibleForTesting
Map<String, Object?> schemaUiResponseForTesting(
  String id,
  RpcUiResponse response,
) => PiRpcProcess._schemaUiResponse(id, response);

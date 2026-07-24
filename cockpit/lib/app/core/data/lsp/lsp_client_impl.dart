import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/lsp/lsp_codec.dart';
import 'package:cockpit/app/core/data/lsp/lsp_process_registry.dart';
import 'package:cockpit/app/core/data/setup/outpost_pi_resolver.dart';
import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/exceptions/lsp_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter/foundation.dart';

/// Implement [LspClient] over a `dart:io` [Process].
///
/// Owns the lifecycle of **one** language server: spawning it, writing framed
/// messages to stdin with [encodeLspMessage], parsing stdout through
/// [LspMessageDecoder], performing the LSP handshake, publishing diagnostics,
/// and shutting it down cleanly.
///
/// Mirrors the `PiRpcProcess` pattern (serialized write chain, one completer per
/// id, close stdin → SIGTERM → SIGKILL). It differs in framing (Content-Length,
/// not JSONL) and JSON-RPC ids (integers, not `req-N`).
class LspClientImpl implements LspClient {
  LspClientImpl({required this.spec, required this.rootPath});

  final LspServerSpec spec;

  @override
  final String rootPath;

  final StreamController<LspDiagnosticsBatch> _diagnostics =
      StreamController<LspDiagnosticsBatch>.broadcast();

  /// Pending requests waiting for the response with the matching `id`.
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  int _seq = 0;

  /// Serialize writes to stdin (see `PiRpcProcess._writeChain`).
  Future<void> _writeChain = Future<void>.value();

  Process? _process;
  StreamSubscription<Map<String, dynamic>>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _initialized = false;
  int _stderrLineCount = 0;

  @override
  Stream<LspDiagnosticsBatch> get diagnostics => _diagnostics.stream;

  @override
  bool get isRunning => _process != null;

  @override
  Future<Result<void, LspError>> start() async {
    if (_process != null) {
      return const Failure(LspError('Language server already running.'));
    }
    try {
      // Apply the same precaution as pi: servers such as
      // typescript-language-server/intelephense are shims that need `node` on
      // PATH (macOS GUI apps do not inherit the shell environment).
      final env = await envWithNodeOnPath();
      final process = await Process.start(
        spec.executable,
        spec.args,
        workingDirectory: rootPath,
        environment: env,
        runInShell: Platform.isWindows,
      );
      _process = process;
      _stderrLineCount = 0;
      unawaited(LspProcessRegistry.register(process.pid));

      _stdoutSub = process.stdout
          .transform(const LspMessageDecoder())
          .listen(_onMessage, onError: _onStreamError);

      _stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onStderrLine, onError: _onStreamError);

      unawaited(process.exitCode.then(_onExit));

      await _handshake();
      return const Success(null);
    } catch (error, stackTrace) {
      _process = null;
      return Failure(
        LspError(
          'Failed to start "${spec.executable}": $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Complete the `initialize` → `initialized` handshake.
  ///
  /// Advertises the minimum capabilities in use (publishDiagnostics and, in
  /// Wave 3, formatting). Leaves `positionEncoding` at its default (UTF-16),
  /// matching Dart [String] code units.
  Future<void> _handshake() async {
    final rootUri = Uri.directory(rootPath).toString();
    await _request('initialize', <String, dynamic>{
      'processId': pid,
      'rootUri': rootUri,
      'workspaceFolders': <Map<String, dynamic>>[
        {'uri': rootUri, 'name': rootPath.split(Platform.pathSeparator).last},
      ],
      'capabilities': <String, dynamic>{
        'textDocument': <String, dynamic>{
          'publishDiagnostics': <String, dynamic>{'relatedInformation': false},
          'synchronization': <String, dynamic>{
            'didSave': true,
            'dynamicRegistration': false,
          },
          'formatting': <String, dynamic>{'dynamicRegistration': false},
        },
      },
    });
    _notify('initialized', <String, dynamic>{});
    _initialized = true;
  }

  @override
  Future<void> didOpen({required String path, required String text}) async {
    if (!_initialized) return;
    _notify('textDocument/didOpen', <String, dynamic>{
      'textDocument': <String, dynamic>{
        'uri': _uri(path),
        'languageId': spec.languageId,
        'version': 1,
        'text': text,
      },
    });
  }

  @override
  Future<void> didChange({
    required String path,
    required String text,
    required int version,
  }) async {
    if (!_initialized) return;
    _notify('textDocument/didChange', <String, dynamic>{
      'textDocument': <String, dynamic>{'uri': _uri(path), 'version': version},
      // Full sync sends the entire document after every edit. This is simple
      // and sufficient for the file sizes opened by the editor.
      'contentChanges': <Map<String, dynamic>>[
        {'text': text},
      ],
    });
  }

  @override
  Future<void> didClose({required String path}) async {
    if (!_initialized) return;
    _notify('textDocument/didClose', <String, dynamic>{
      'textDocument': <String, dynamic>{'uri': _uri(path)},
    });
  }

  @override
  Future<Result<Object?, LspError>> request(
    String method,
    Map<String, dynamic> params,
  ) async {
    try {
      return Success(await _request(method, params));
    } on LspError catch (error) {
      return Failure(error);
    } catch (error, stackTrace) {
      return Failure(LspError('$error', cause: error, stackTrace: stackTrace));
    }
  }

  @override
  Future<void> kill() async {
    final process = _process;
    if (process == null) return;
    // Graceful LSP path: shutdown (request) → exit (notification) → close stdin.
    try {
      await _request(
        'shutdown',
        const <String, dynamic>{},
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      _notify('exit', const <String, dynamic>{});
    } catch (_) {}
    try {
      await process.stdin.close();
    } catch (_) {}

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
  }

  @override
  void dispose() {
    final process = _process;
    if (process != null) {
      try {
        process.stdin.close();
      } catch (_) {}
      process.kill(ProcessSignal.sigterm);
    }
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    if (!_diagnostics.isClosed) _diagnostics.close();
  }

  // --- wire ---

  String _uri(String path) => Uri.file(path).toString();

  void _onMessage(Map<String, dynamic> message) {
    // A response to one of our requests has an `id` and either `result` or
    // `error`, but no `method`.
    final id = message['id'];
    final method = message['method'];
    if (method == null && id is int) {
      final completer = _pending.remove(id);
      if (completer != null && !completer.isCompleted) {
        final error = message['error'];
        if (error != null) {
          completer.completeError(
            LspError('LSP error: ${error is Map ? error['message'] : error}'),
          );
        } else {
          completer.complete(message['result']);
        }
      }
      return;
    }

    // A server-to-client request has both `id` and `method`; it needs a
    // response to avoid blocking the server. Return the minimum viable result.
    if (method is String && id != null) {
      _handleServerRequest(id, method);
      return;
    }

    // A server-to-client notification has `method` but no `id`.
    if (method is String) _handleNotification(method, message['params']);
  }

  void _handleServerRequest(Object id, String method) {
    final Object? result = switch (method) {
      // Configuration: return one null item per requested scope to use defaults.
      'workspace/configuration' => <Object?>[null],
      // Dynamic capability registration is accepted as a client-side no-op.
      'client/registerCapability' ||
      'client/unregisterCapability' ||
      'window/workDoneProgress/create' => null,
      _ => null,
    };
    _send(<String, dynamic>{'jsonrpc': '2.0', 'id': id, 'result': result});
  }

  void _handleNotification(String method, Object? params) {
    if (method == 'textDocument/publishDiagnostics' &&
        params is Map<String, dynamic>) {
      final uri = params['uri'] as String? ?? '';
      final raw = params['diagnostics'];
      final list = <LspDiagnostic>[
        if (raw is List)
          for (final d in raw)
            if (d is Map<String, dynamic>) LspDiagnostic.fromJson(d),
      ];
      if (!_diagnostics.isClosed) {
        _diagnostics.add(LspDiagnosticsBatch(uri: uri, diagnostics: list));
      }
    }
    // Other notifications (logMessage, progress, …) are currently ignored.
  }

  Future<Object?> _request(String method, Map<String, dynamic> params) async {
    if (_process == null) throw const LspError('Language server not running.');
    final id = ++_seq;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _send(<String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pending.remove(id);
        throw LspError('Timed out waiting for "$method".');
      },
    );
  }

  void _notify(String method, Map<String, dynamic> params) {
    if (_process == null) return;
    _send(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  /// Write a message to stdin, serialized with all other writes.
  ///
  /// Uses the same write-chain pattern as `PiRpcProcess`.
  void _send(Map<String, dynamic> message) {
    final bytes = encodeLspMessage(message);
    final result = _writeChain.then((_) async {
      final process = _process;
      if (process == null) return;
      process.stdin.add(bytes);
      await process.stdin.flush();
    });
    _writeChain = result.then((_) {}, onError: (_) {});
  }

  void _onStderrLine(String line) {
    if (line.trim().isEmpty) return;
    _stderrLineCount += 1;
    if (_stderrLineCount == 1) {
      debugPrint(
        '[lsp:${spec.languageId}][err] server diagnostic output '
        '(content hidden)',
      );
    }
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    debugPrint('[lsp:${spec.languageId}] stream error (content hidden)');
  }

  void _onExit(int code) {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    final exitedPid = _process?.pid;
    _process = null;
    _initialized = false;
    if (exitedPid != null) unawaited(LspProcessRegistry.unregister(exitedPid));
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          LspError('Language server exited (code=$code).'),
        );
      }
    }
    _pending.clear();
    debugPrint(
      '[lsp:${spec.languageId}] exited code=$code '
      'stderrLines=$_stderrLineCount',
    );
  }
}

/// Create an [LspClientImpl] for each language-server root.
class LspClientFactoryImpl implements LspClientFactory {
  const LspClientFactoryImpl();

  @override
  LspClient create({required LspServerSpec spec, required String rootPath}) =>
      LspClientImpl(spec: spec, rootPath: rootPath);
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/core/data/rpc/jsonl_line_splitter.dart';
import 'package:cockpit/app/core/data/setup/outpost_pi_resolver.dart';

/// Define the process boundary for a one-off outpost-pi RPC session.
///
/// Implementations start a process, deliver decoded stdout JSON to [onLine], and
/// must dispose its process and temporary working directory at the end of the
/// owning operation.
abstract interface class EphemeralPiRpcSession {
  /// Start the RPC process and submit [prompt].
  Future<void> start({
    required String prompt,
    required void Function(Map<String, dynamic> json) onLine,
    void Function(int code)? onExit,
    Map<String, String> additionalEnvironment,
  });

  /// Stop the RPC process and release its temporary resources.
  Future<void> dispose();
}

/// Run one-off outpost-pi commands in a dedicated ephemeral RPC session.
///
/// Starts `pi --mode rpc --no-session` in a unique temporary directory to avoid
/// cwd-lock collisions. Supplies a pairing `OUTPOST_PI_DIRECT_CONFIG`, making
/// `localConfigExists` true so `/outpost-pi <cmd>` connects to the relay
/// automatically. The outpost-pi extension remains enabled; this deliberately
/// omits `--no-extensions`.
///
/// Does not interpret the protocol. Each stdout JSON object is delivered through
/// [onLine] for the caller to classify as a response or event. [dispose]
/// idempotently prevents orphan processes and removes the temporary directory.
class EphemeralPiRpc implements EphemeralPiRpcSession {
  EphemeralPiRpc(this._config);

  final PiSpawnConfig _config;

  Process? _process;
  Directory? _tempDir;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  bool _disposed = false;

  /// Start the process and send [prompt] as one JSON line.
  ///
  /// Delivers each stdout JSON object to [onLine] and, when supplied, the exit
  /// code to [onExit]. [additionalEnvironment] carries operation-owned process
  /// inputs such as the pairing-code file path. Throws when the process cannot
  /// be spawned.
  @override
  Future<void> start({
    required String prompt,
    required void Function(Map<String, dynamic> json) onLine,
    void Function(int code)? onExit,
    Map<String, String> additionalEnvironment = const <String, String>{},
  }) async {
    final dir = await Directory.systemTemp.createTemp('outpost-pi-rpc-');
    _tempDir = dir;

    final env = <String, String>{
      // Put the `node` binary on PATH for pi's `#!/usr/bin/env node` shim.
      ...await envWithNodeOnPath(),
      'OUTPOST_PI_DIRECT_CONFIG': jsonEncode(<String, dynamic>{
        'agent_name': _randomName(),
        'workspace': 'pairing',
      }),
      ...additionalEnvironment,
    };

    final process = await Process.start(
      _config.executable,
      _args(),
      workingDirectory: dir.path,
      environment: env,
      // On Windows, pi is an npm `.cmd`/`.bat` shim and requires the shell.
      runInShell: Platform.isWindows,
    );
    _process = process;

    _stdoutSub = process.stdout.transform(const JsonlLineSplitter()).listen((
      line,
    ) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map<String, dynamic>) onLine(decoded);
      } catch (_) {
        // Ignore a non-JSON line without terminating the command.
      }
    }, onError: (_) {});
    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((_) {}, onError: (_) {});

    if (onExit != null) unawaited(process.exitCode.then(onExit));

    process.stdin.write('$prompt\n');
    await process.stdin.flush();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        await process.stdin.close(); // Graceful shutdown (code 0).
      } catch (_) {}
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigterm);
      }
    }
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    final dir = _tempDir;
    _tempDir = null;
    if (dir != null) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Build arguments for a non-persistent RPC session with extensions enabled.
  ///
  /// The outpost-pi slash commands require the extension, so the arguments
  /// deliberately omit `--no-extensions`.
  List<String> _args() => <String>[
    '--mode',
    'rpc',
    '--no-session',
    if (_config.provider != null && _config.provider!.isNotEmpty) ...[
      '--provider',
      _config.provider!,
    ],
    if (_config.model != null && _config.model!.isNotEmpty) ...[
      '--model',
      _config.model!,
    ],
  ];

  static String _randomName() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    final suffix = List<String>.generate(
      6,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    return 'pairing-$suffix';
  }
}

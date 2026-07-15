import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/settings/data/daemon/win_named_pipe.dart';
import 'package:cockpit/app/core/data/setup/outpost_pi_resolver.dart';
import 'package:cockpit/app/settings/domain/contracts/cron_gateway.dart';
import 'package:cockpit/app/settings/domain/contracts/daemon_supervisor.dart';
import 'package:cockpit/app/settings/domain/entities/cron_job.dart';
import 'package:cockpit/app/settings/domain/entities/daemon_info.dart';
import 'package:cockpit/app/settings/domain/exceptions/daemon_error.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Adapt [DaemonSupervisor] and [CronGateway] to the same control plane.
///
/// **Control** uses the `~/.pi/remote/supervisor.sock` UDS with line-delimited
/// JSON (one request → one reply → close), mirroring
/// `pi-extension/src/daemon/client.ts`. **Creation** shells out to
/// `outpost-pi create`, which writes the local config, registers the daemon,
/// and starts it; the UDS `register` operation does not write config. Cron
/// (plan/39) uses the `cron_*` operations on the same socket.
class SupervisorClientImpl implements DaemonSupervisor, CronGateway {
  SupervisorClientImpl();

  Future<({String exe, List<String> prefixArgs})?>? _resolvedCli;

  // Windows does not set HOME; its equivalent is USERPROFILE.
  String? get _home =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  String? _sockPath() {
    final home = _home;
    return home == null ? null : '$home/.pi/remote/supervisor.sock';
  }

  @override
  Future<bool> isOnline() async {
    // On Windows, the supervisor listens on a named pipe, so no socket file
    // exists. A non-null `list` transaction proves that the pipe is accepting
    // requests.
    if (Platform.isWindows) {
      final reply = await winPipeTransact(
        supervisorPipeName(),
        '${jsonEncode(<String, dynamic>{'op': 'list'})}\n',
        timeout: const Duration(seconds: 1),
      );
      return reply != null;
    }
    final path = _sockPath();
    if (path == null || !await File(path).exists()) return false;
    try {
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      ).timeout(const Duration(seconds: 1));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Result<List<DaemonInfo>, DaemonError>> list() async {
    final result = await _call(<String, dynamic>{'op': 'list'});
    return result.map((data) {
      final raw = data['daemons'];
      if (raw is! List) return const <DaemonInfo>[];
      return raw.whereType<Map>().map(_toDaemon).toList(growable: false);
    });
  }

  @override
  Future<Result<void, DaemonError>> start(String id) => _unit('start', id: id);
  @override
  Future<Result<void, DaemonError>> stop(String id) => _unit('stop', id: id);
  @override
  Future<Result<void, DaemonError>> restart(String id) =>
      _unit('restart', id: id);

  @override
  Future<Result<void, DaemonError>> startAll() => _unit('start_all');
  @override
  Future<Result<void, DaemonError>> stopAll() => _unit('stop_all');
  @override
  Future<Result<void, DaemonError>> restartAll() => _unit('restart_all');

  @override
  Future<Result<void, DaemonError>> unregister(String id) =>
      _unit('unregister', id: id);

  @override
  Future<Result<void, DaemonError>> create(String cwd, {String? name}) async {
    try {
      final result = await _runCli(<String>[
        'create',
        cwd,
        if (name != null && name.trim().isNotEmpty) ...['--name', name.trim()],
      ]);
      if (result == null) {
        return const Failure(
          DaemonError('Could not find outpost-pi (install the extension).'),
        );
      }
      if (result.exitCode != 0) {
        final err = (result.stderr as String? ?? '').trim();
        final out = (result.stdout as String? ?? '').trim();
        final msg = err.isNotEmpty
            ? err
            : (out.isNotEmpty ? out : 'Failed to create the daemon.');
        return Failure(DaemonError(msg));
      }
      return const Success(null);
    } catch (error, stackTrace) {
      return Failure(
        DaemonError(
          'Failed to create the daemon: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void, DaemonError>> setAgentName(
    String cwd,
    String name,
  ) async {
    // The global `~/.pi/remote/daemons.json` registry (`{cwd, name}`) is the
    // source of truth for the name; the supervisor injects it at spawn through
    // OUTPOST_PI_DIRECT_CONFIG. There is no per-folder local config or rename
    // operation/CLI, so edit the registry directly. The ViewModel's
    // `restart(id)` then respawns the daemon with the new name.
    final home = _home;
    if (home == null) {
      return const Failure(DaemonError('HOME not found in the environment.'));
    }
    try {
      final file = File('$home/.pi/remote/daemons.json');
      if (!await file.exists()) {
        return const Failure(DaemonError('Daemon registry not found.'));
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['daemons'] is! List) {
        return const Failure(DaemonError('Invalid daemon registry.'));
      }
      var found = false;
      for (final item in decoded['daemons'] as List) {
        if (item is Map && item['cwd'] == cwd) {
          item['name'] = name;
          found = true;
          break;
        }
      }
      if (!found) {
        return const Failure(DaemonError('Daemon not found in the registry.'));
      }
      // Match pi-extension's saveRegistry format: two-space indent and final LF.
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
      );
      return const Success(null);
    } catch (error, stackTrace) {
      return Failure(
        DaemonError(
          'Failed to rename the agent: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void, DaemonError>> restartSupervisor() async {
    // Delegate to `outpost-pi restart-supervisor`, which handles each platform:
    // launchctl on macOS, systemctl on Linux, and a service on Windows. This
    // keeps OS-specific logic in outpost-pi instead of duplicating it here.
    try {
      final result = await _runCli(const ['restart-supervisor']);
      if (result == null) {
        return const Failure(
          DaemonError('Could not find outpost-pi (install the extension).'),
        );
      }
      final out = (result.stdout as String? ?? '');
      final err = (result.stderr as String? ?? '');
      // The CLI prints help and exits with 0 when the command is unavailable,
      // so exitCode alone is insufficient. Treat its usage banner as proof that
      // the command is unavailable.
      if ('$out\n$err'.contains('Usage: outpost-pi')) {
        return const Failure(
          DaemonError(
            'This outpost-pi does not have the `restart-supervisor` command yet. '
            'Update outpost-pi.',
          ),
        );
      }
      if (result.exitCode != 0) {
        final e = err.trim();
        final o = out.trim();
        final msg = e.isNotEmpty
            ? e
            : (o.isNotEmpty ? o : 'Failed to restart the supervisor.');
        return Failure(DaemonError(msg));
      }
      return const Success(null);
    } catch (error, stackTrace) {
      return Failure(
        DaemonError(
          'Failed to restart the supervisor: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ---- cron (plan/39) -------------------------------------------------------

  @override
  Future<Result<List<CronJob>, DaemonError>> listCron() async {
    final result = await _call(<String, dynamic>{'op': 'cron_list'});
    return result.map((data) {
      final raw = data['jobs'];
      if (raw is! List) return const <CronJob>[];
      return raw.whereType<Map>().map(_toCronJob).toList(growable: false);
    });
  }

  @override
  Future<Result<void, DaemonError>> addCron({
    required String daemonId,
    required String schedule,
    required String prompt,
    String? tz,
    bool skipIfBusy = true,
    bool wake = false,
    bool catchup = false,
  }) => _voidCall(<String, dynamic>{
    'op': 'cron_add',
    'daemon_id': daemonId,
    'schedule': schedule,
    'prompt': prompt,
    'tz': ?tz,
    'skip_if_busy': skipIfBusy,
    'wake': wake,
    'catchup': catchup,
  });

  @override
  Future<Result<void, DaemonError>> removeCron(String jobId) =>
      _voidCall(<String, dynamic>{'op': 'cron_remove', 'job_id': jobId});

  @override
  Future<Result<void, DaemonError>> setCronEnabled(
    String jobId,
    bool enabled,
  ) => _voidCall(<String, dynamic>{
    'op': 'cron_enable',
    'job_id': jobId,
    'enabled': enabled,
  });

  @override
  Future<Result<String, DaemonError>> runCron(String jobId) async {
    final result = await _call(<String, dynamic>{
      'op': 'cron_run',
      'job_id': jobId,
    });
    return result.map((data) => data['result']?.toString() ?? 'unknown');
  }

  @override
  Future<Result<List<CronLogEntry>, DaemonError>> cronLog({
    String? jobId,
    int? tail,
  }) async {
    final result = await _call(<String, dynamic>{
      'op': 'cron_log',
      'job_id': ?jobId,
      'tail': ?tail,
    });
    return result.map((data) {
      final raw = data['entries'];
      if (raw is! List) return const <CronLogEntry>[];
      return raw.whereType<Map>().map(_toCronLog).toList(growable: false);
    });
  }

  CronJob _toCronJob(Map<dynamic, dynamic> j) {
    bool b(Object? v, bool fallback) => v is bool ? v : fallback;
    return CronJob(
      id: j['id']?.toString() ?? '',
      daemonId: j['daemon_id']?.toString() ?? '',
      schedule: j['schedule']?.toString() ?? '',
      prompt: j['prompt']?.toString() ?? '',
      enabled: b(j['enabled'], true),
      skipIfBusy: b(j['skip_if_busy'], true),
      wake: b(j['wake'], false),
      catchup: b(j['catchup'], false),
      tz: j['tz']?.toString(),
      createdAt: j['created_at']?.toString(),
      lastRun: j['last_run']?.toString(),
      lastStatus: j['last_status']?.toString(),
      nextRun: j['next_run']?.toString(),
    );
  }

  CronLogEntry _toCronLog(Map<dynamic, dynamic> e) {
    final ts = e['ts'];
    return CronLogEntry(
      tsMs: ts is num ? ts.toInt() : 0,
      jobId: e['job_id']?.toString() ?? '',
      daemonId: e['daemon_id']?.toString() ?? '',
      schedule: e['schedule']?.toString() ?? '',
      fired: e['fired'] == true,
      result: cronResultFromWire(e['result'] as String?),
      promptPreview: e['prompt_preview']?.toString() ?? '',
    );
  }

  // ---- UDS internals --------------------------------------------------------

  /// Call the supervisor and discard `data` for operations whose only success
  /// signal is `{ok:true}`.
  Future<Result<void, DaemonError>> _voidCall(Map<String, dynamic> req) async {
    final result = await _call(req);
    return result.fold((_) => const Success(null), (error) => Failure(error));
  }

  Future<Result<void, DaemonError>> _unit(String op, {String? id}) async {
    final result = await _call(<String, dynamic>{'op': op, 'id': ?id});
    return result.fold((_) => const Success(null), (error) => Failure(error));
  }

  /// Open the supervisor transport, send one JSON line, read one reply line,
  /// and close it.
  ///
  /// Returns `data` for `{ok:true}`; maps `{ok:false}` and transport failures
  /// to [DaemonError].
  Future<Result<Map<String, dynamic>, DaemonError>> _call(
    Map<String, dynamic> request,
  ) async {
    try {
      final line = await _transact('${jsonEncode(request)}\n');
      if (line == null) {
        return const Failure(DaemonError('Could not reach the supervisor.'));
      }
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        return const Failure(
          DaemonError('Invalid response from the supervisor.'),
        );
      }
      if (decoded['ok'] == true) {
        final data = decoded['data'];
        return Success(data is Map<String, dynamic> ? data : const {});
      }
      return Failure(
        DaemonError((decoded['error'] as String?) ?? 'Supervisor error.'),
      );
    } on TimeoutException {
      return const Failure(DaemonError('Timed out talking to the supervisor.'));
    } catch (error, stackTrace) {
      return Failure(
        DaemonError(
          'Supervisor failure: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Perform one request → one reply transaction with the supervisor.
  ///
  /// Windows uses a named pipe and POSIX uses the UDS. Returns the reply line
  /// without `\n`, or `null` when the supervisor is offline.
  Future<String?> _transact(String requestLine) async {
    if (Platform.isWindows) {
      return winPipeTransact(supervisorPipeName(), requestLine);
    }
    final path = _sockPath();
    if (path == null || !await File(path).exists()) return null;
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      ).timeout(const Duration(seconds: 2));
      socket.write(requestLine);
      await socket.flush();
      return await _readLine(socket).timeout(const Duration(seconds: 6));
    } on SocketException {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  Future<String> _readLine(Socket socket) {
    final completer = Completer<String>();
    final buffer = StringBuffer();
    late StreamSubscription<String> sub;
    sub = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            buffer.write(chunk);
            final text = buffer.toString();
            final nl = text.indexOf('\n');
            if (nl >= 0 && !completer.isCompleted) {
              completer.complete(text.substring(0, nl));
              unawaited(sub.cancel());
            }
          },
          onError: (Object e) {
            if (!completer.isCompleted) completer.completeError(e);
          },
          onDone: () {
            if (!completer.isCompleted) {
              final text = buffer.toString();
              completer.complete(text.isEmpty ? '' : text);
            }
          },
        );
    return completer.future;
  }

  DaemonInfo _toDaemon(Map<dynamic, dynamic> json) {
    int? asInt(Object? v) => v is num ? v.toInt() : null;
    return DaemonInfo(
      id: json['id']?.toString() ?? '',
      cwd: json['cwd']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      state: daemonStateFromWire(json['state'] as String?),
      pid: asInt(json['pid']),
      uptimeSeconds: asInt(json['uptime_s']),
      restartCount: asInt(json['restart_count']),
    );
  }

  // ---- CLI resolution -------------------------------------------------------

  /// Resolve how to invoke `outpost-pi`: a binary on POSIX or
  /// `node <index.js>` on Windows.
  Future<({String exe, List<String> prefixArgs})?> _cli() =>
      _resolvedCli ??= resolveOutpostPiCommand();

  /// Run the platform-resolved `outpost-pi <args>` command.
  ///
  /// Includes `node` on PATH because the shim uses `#!/usr/bin/env node`, and
  /// enables `runInShell` on Windows.
  Future<ProcessResult?> _runCli(List<String> args) async {
    final cmd = await _cli();
    if (cmd == null) return null;
    return Process.run(
      cmd.exe,
      [...cmd.prefixArgs, ...args],
      runInShell: Platform.isWindows,
      environment: await envWithNodeOnPath(),
    );
  }
}

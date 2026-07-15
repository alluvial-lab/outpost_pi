import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/core/data/setup/outpost_pi_resolver.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/utils/executable_resolver.dart';

/// Split a command line into tokens while honoring single and double quotes.
///
/// Supports paths containing spaces but does not expand variables.
List<String> splitLspCommand(String command) {
  final tokens = <String>[];
  final buf = StringBuffer();
  String? quote;
  for (var i = 0; i < command.length; i++) {
    final ch = command[i];
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else {
        buf.write(ch);
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
    } else if (ch == ' ' || ch == '\t') {
      if (buf.isNotEmpty) {
        tokens.add(buf.toString());
        buf.clear();
      }
    } else {
      buf.write(ch);
    }
  }
  if (buf.isNotEmpty) tokens.add(buf.toString());
  return tokens;
}

/// Probe whether [command] behaves like a valid language server.
///
/// Spawns the process and checks whether it remains alive for a short interval.
/// A real LSP waits for `initialize` on stdin, while an invalid command such as
/// `dart language-serve` prints usage and exits immediately with a nonzero code.
///
/// This validates arguments as well as finding the binary on PATH. The probe
/// always kills a process it successfully starts and returns `false` when the
/// process cannot be spawned.
Future<bool> probeLspCommand(String command) async {
  final parts = splitLspCommand(command.trim());
  if (parts.isEmpty) return false;
  final exec = await resolveExecutable(parts.first);

  Process? process;
  try {
    process = await Process.start(
      exec,
      parts.sublist(1),
      environment: await envWithNodeOnPath(),
      runInShell: Platform.isWindows,
    );
  } catch (_) {
    return false; // The binary is missing or invalid and could not be spawned.
  }

  // Drain both streams so a full buffer cannot block the process.
  final proc = process;
  unawaited(proc.stdout.drain<void>().catchError((_) {}));
  unawaited(proc.stderr.drain<void>().catchError((_) {}));

  // An early exit is invalid; remaining alive suggests a real LSP.
  var aliveAfterWindow = false;
  try {
    await proc.exitCode.timeout(const Duration(milliseconds: 1200));
  } on TimeoutException {
    aliveAfterWindow = true;
  }

  proc.kill(ProcessSignal.sigkill);
  return aliveAfterWindow;
}

/// Run an external formatter such as `prettier --write %FILE%` on [filePath].
///
/// Replaces `%FILE%` in every argument with the path. The formatter operates on
/// the file directly and may rewrite it on disk. Returns success for exit code
/// zero; otherwise returns stderr, or the exit code when stderr is empty.
Future<Result<void, String>> runFormatterCommand(
  String command,
  String filePath,
) async {
  final parts = splitLspCommand(command.trim());
  if (parts.isEmpty) return const Failure('Empty formatter command.');
  if (!command.contains('%FILE%')) {
    return const Failure(
      'Formatter command must include the %FILE% placeholder.',
    );
  }
  final substituted = parts
      .map((t) => t.replaceAll('%FILE%', filePath))
      .toList();
  final exec = await resolveExecutable(substituted.first);
  try {
    final r = await Process.run(
      exec,
      substituted.sublist(1),
      environment: await envWithNodeOnPath(),
      runInShell: Platform.isWindows,
    ).timeout(const Duration(seconds: 30));
    if (r.exitCode == 0) return const Success(null);
    final err = (r.stderr as String? ?? '').trim();
    return Failure(err.isEmpty ? 'Formatter exited with ${r.exitCode}.' : err);
  } on TimeoutException {
    return const Failure('Formatter timed out.');
  } catch (e) {
    return Failure('$e');
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Capture failure-path diagnostics and reject any registered sensitive value.
final class FailureLogRedactionCanary {
  FailureLogRedactionCanary._({
    required this.composeProject,
    required this.composeFile,
    required this.canaryFile,
    required DebugPrintCallback previousDebugPrint,
  }) : _previousDebugPrint = previousDebugPrint;

  factory FailureLogRedactionCanary.start() {
    const composeProject = String.fromEnvironment('E2E_COMPOSE_PROJECT');
    const composeFile = String.fromEnvironment('E2E_COMPOSE_FILE');
    const canaryFile = String.fromEnvironment('E2E_REDACTION_CANARY_FILE');
    if (composeProject.isEmpty || composeFile.isEmpty || canaryFile.isEmpty) {
      throw StateError('redaction diagnostics were not provided by the runner');
    }

    final previous = debugPrint;
    final canary = FailureLogRedactionCanary._(
      composeProject: composeProject,
      composeFile: composeFile,
      canaryFile: canaryFile,
      previousDebugPrint: previous,
    );
    debugPrint = (message, {wrapWidth}) {
      if (message != null) canary._flutterDiagnostics.writeln(message);
      previous(message, wrapWidth: wrapWidth);
    };
    return canary;
  }

  final String composeProject;
  final String composeFile;
  final String canaryFile;
  final DebugPrintCallback _previousDebugPrint;
  final StringBuffer _flutterDiagnostics = StringBuffer();
  final Map<String, String> _canaries = <String, String>{};
  bool _verified = false;

  /// Register real wire/runtime values without rendering them in test output.
  Future<void> register(Map<String, String> values) async {
    final file = File(canaryFile);
    for (final entry in values.entries) {
      if (entry.value.length < 8) {
        throw StateError('redaction canary is too short: ${entry.key}');
      }
      _canaries[entry.key] = entry.value;
      await file.writeAsString(
        '${jsonEncode(<String, String>{'label': entry.key, 'value': entry.value})}\n',
        mode: FileMode.append,
        flush: true,
      );
    }
  }

  /// Assert Flutter, Pi-host, and relay diagnostics omit every canary.
  Future<void> verify() async {
    if (_verified) return;
    _verified = true;
    debugPrint = _previousDebugPrint;

    final piHostLogs = await _serviceLogs('pi-host');
    final relayLogs = await _serviceLogs('relay');
    final diagnostics = StringBuffer(_flutterDiagnostics.toString())
      ..writeln(piHostLogs)
      ..writeln(relayLogs);
    final captured = diagnostics.toString();

    if (_canaries.isEmpty) {
      fail('redaction check registered no sensitive canaries');
    }
    for (final entry in _canaries.entries) {
      if (!captured.contains(entry.value)) continue;
      final fingerprint = sha256
          .convert(utf8.encode(entry.value))
          .toString()
          .substring(0, 12);
      fail(
        'sensitive diagnostic canary leaked: '
        '${entry.key} (sha256:$fingerprint)',
      );
    }
  }

  Future<String> _serviceLogs(String service) async {
    final result = await Process.run('docker', <String>[
      'compose',
      '-p',
      composeProject,
      '-f',
      composeFile,
      'logs',
      '--no-color',
      service,
    ]);
    if (result.exitCode != 0) {
      fail(
        'could not capture $service diagnostics '
        '(docker compose exit ${result.exitCode})',
      );
    }
    return '${result.stdout}\n${result.stderr}';
  }
}

import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/core/data/relay/ephemeral_pi_rpc.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EphemeralPiRpc.dispose', () {
    test(
      'escalates from an ignored SIGTERM to SIGKILL and awaits final exit',
      () async {
        final process = _FakeProcess();
        var exitWaits = 0;
        final rpc = _rpc(
          process,
          waitForExit: (exitCode) {
            exitWaits += 1;
            if (exitWaits < 3) {
              return Future<void>.error(TimeoutException('controlled timeout'));
            }
            return exitCode.then<void>((_) {});
          },
        );
        await _start(rpc);

        var disposed = false;
        final disposing = rpc.dispose().whenComplete(() => disposed = true);
        await process.sigkillSent.future;

        expect(process.signals, <ProcessSignal>[
          ProcessSignal.sigterm,
          ProcessSignal.sigkill,
        ]);
        expect(disposed, isFalse);
        expect(Directory(process.workingDirectory!).existsSync(), isTrue);

        process.exit(9);
        await disposing;
        expect(disposed, isTrue);
        expect(Directory(process.workingDirectory!).existsSync(), isFalse);
      },
    );

    test(
      'does not escalate when the process exits during graceful shutdown',
      () async {
        final process = _FakeProcess();
        final rpc = _rpc(
          process,
          waitForExit: (exitCode) {
            process.exit(0);
            return exitCode.then<void>((_) {});
          },
        );
        await _start(rpc);

        await rpc.dispose();

        expect(process.signals, isEmpty);
      },
    );
  });
}

EphemeralPiRpc _rpc(
  _FakeProcess process, {
  required Future<void> Function(Future<int> exitCode) waitForExit,
}) => EphemeralPiRpc(
  const PiSpawnConfig(executable: 'pi'),
  processStarter:
      (
        executable,
        arguments, {
        required workingDirectory,
        required environment,
        required runInShell,
      }) async {
        process.workingDirectory = workingDirectory;
        return process;
      },
  waitForExit: waitForExit,
);

Future<void> _start(EphemeralPiRpc rpc) => rpc.start(
  prompt: '{"type":"prompt","message":"/outpost-pi pair"}',
  onLine: (_) {},
);

final class _FakeProcess implements Process {
  final Completer<int> _exitCode = Completer<int>();
  final Completer<void> sigkillSent = Completer<void>();
  final List<ProcessSignal> signals = <ProcessSignal>[];
  String? workingDirectory;
  final IOSink _stdin = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'outpost-pi-ephemeral-rpc-test-${DateTime.now().microsecondsSinceEpoch}',
  ).openWrite();

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 1;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (signal == ProcessSignal.sigkill && !sigkillSent.isCompleted) {
      sigkillSent.complete();
    }
    return true;
  }

  void exit(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }
}

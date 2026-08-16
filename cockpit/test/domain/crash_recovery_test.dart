import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/data/hive_box_opener.dart';
import 'package:cockpit/app/core/ui/bootstrap_error_screen.dart';
import 'package:cockpit/app/core/utils/spawn_directory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('deleted workspace becomes an explicit terminal error state', () async {
    final root = await Directory.systemTemp.createTemp('cockpit-crash-');
    final requested = '${root.path}/deleted-workspace';
    final gateway = _Gateway();
    final session = TerminalSession(
      id: 'terminal-1',
      projectId: 'project-1',
      workingDirectory: requested,
      gateway: gateway,
    );

    expect(session.startupError, contains('missing'));
    expect(session.startupError, contains(requested));
    await session.close();
    await root.delete(recursive: true);
  });

  test('Hive-style file lock retries before succeeding', () async {
    var attempts = 0;
    final result = await withFileSystemRetry<String>(
      () async {
        attempts++;
        if (attempts < 4) throw const FileSystemException('locked');
        return 'opened';
      },
      attempts: 5,
      delay: Duration.zero,
    );

    expect(result, 'opened');
    expect(attempts, 4);
  });

  test('Hive-style file lock stops at the bounded retry limit', () async {
    var attempts = 0;
    await expectLater(
      withFileSystemRetry<void>(
        () async {
          attempts++;
          throw const FileSystemException('locked');
        },
        attempts: 3,
        delay: Duration.zero,
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(attempts, 3);
  });

  testWidgets('bootstrap failures render an error screen', (tester) async {
    await tester.pumpWidget(
      const BootstrapErrorApp(error: FileSystemException('locked')),
    );

    expect(find.text('Cockpit could not start'), findsOneWidget);
    expect(find.textContaining('locked'), findsOneWidget);
  });
}

final class _Gateway implements TerminalGateway, TerminalSpawnDirectory {
  final _output = StreamController<List<int>>.broadcast();

  @override
  SpawnDirectory? get spawnDirectory => _resolved;

  SpawnDirectory? _resolved;

  @override
  Stream<List<int>> get output => _output.stream;

  @override
  Future<void> kill() async => _output.close();

  @override
  void resize(int rows, int columns) {}

  @override
  void start({
    required String workingDirectory,
    int rows = 25,
    int columns = 80,
  }) {
    _resolved = resolveSpawnDirectory(workingDirectory);
  }

  @override
  void write(List<int> data) {}
}

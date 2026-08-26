import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/storage/json_state_store.dart';
import 'package:cockpit/app/core/data/storage/legacy_hive_migrator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;
  late String legacyDirectory;
  late String stateDirectory;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cockpit-hive-migrate-');
    legacyDirectory = p.join(temporary.path, 'legacy');
    stateDirectory = p.join(temporary.path, 'state');
    await Directory(legacyDirectory).create(recursive: true);
    await Directory(stateDirectory).create(recursive: true);
  });

  tearDown(() async {
    await Hive.close();
    await temporary.delete(recursive: true);
  });

  LegacyHiveMigrator migrator({
    List<String>? candidates,
    LegacyHiveMigrationDiagnosticSink? diagnostics,
  }) => LegacyHiveMigrator(
    stateDirectory: stateDirectory,
    legacyDirectories:
        candidates ??
        <String>[p.join(temporary.path, 'absent'), legacyDirectory],
    openAttempts: 1,
    retryDelay: Duration.zero,
    diagnostics: diagnostics ?? (_, _) {},
  );

  Map<String, dynamic> readJson(String name) =>
      jsonDecode(File(p.join(stateDirectory, '$name.json')).readAsStringSync())
          as Map<String, dynamic>;

  Map<String, dynamic> readData(String name) =>
      readJson(name)['data'] as Map<String, dynamic>;

  Future<void> seedLegacyBoxes({bool invalidLayoutValue = false}) async {
    Hive.init(legacyDirectory);
    final settings = await Hive.openBox<dynamic>('settings');
    await settings.put('app', <dynamic, dynamic>{
      'themeMode': 'dark',
      'nested': <dynamic, dynamic>{1: 'one'},
    });

    final window = await Hive.openBox<dynamic>('window_state');
    await window.putAll(<dynamic, dynamic>{
      'width': 1280.0,
      'height': 720.0,
      'x': 12.0,
      'y': 24.0,
    });

    final projects = await Hive.openBox<dynamic>('projects');
    await projects.put('project-1', <dynamic, dynamic>{
      'id': 'project-1',
      'name': 'Project',
      'path': '/workspace/project',
      'createdAt': 42,
      'order': 3,
    });
    await projects.put('__last_selected__', 'project-1');

    final layouts = await Hive.openBox<dynamic>('layouts');
    await layouts.put(
      'project-1',
      invalidLayoutValue ? double.infinity : '{"version":1,"tree":{}}',
    );
    await Hive.close();
  }

  test('exports all four boxes and preserves their legacy files', () async {
    await seedLegacyBoxes();

    final result = await migrator().runIfNeeded();

    expect(result.ran, isTrue);
    expect(result.failedStores, isEmpty);
    expect(readData('settings'), <String, Object?>{
      'app': <String, Object?>{
        'themeMode': 'dark',
        'nested': <String, Object?>{'1': 'one'},
      },
    });
    expect(readData('window_state'), <String, Object?>{
      'width': 1280.0,
      'height': 720.0,
      'x': 12.0,
      'y': 24.0,
    });
    expect(readData('projects'), <String, Object?>{
      'project-1': <String, Object?>{
        'id': 'project-1',
        'name': 'Project',
        'path': '/workspace/project',
        'createdAt': 42,
        'order': 3,
      },
      '__last_selected__': 'project-1',
    });
    expect(readData('layouts'), <String, Object?>{
      'project-1': '{"version":1,"tree":{}}',
    });

    for (final String name in LegacyHiveMigrator.storeNames) {
      expect(File(p.join(legacyDirectory, '$name.hive')).existsSync(), isTrue);
      expect(readJson(name)['version'], JsonStateStore.formatVersion);
    }
    expect(readJson('migration'), <String, Object?>{
      'version': 1,
      'source': 'legacy_hive',
      'failedStores': <Object?>[],
    });
  });

  test('marker makes a second run skip without rewriting JSON', () async {
    await seedLegacyBoxes();
    await migrator().runIfNeeded();
    final projectFile = File(p.join(stateDirectory, 'projects.json'));
    const probe = '{"version":1,"data":{"probe":true}}';
    await projectFile.writeAsString(probe);

    final second = await migrator().runIfNeeded();

    expect(second.ran, isFalse);
    expect(second.failedStores, isEmpty);
    expect(await projectFile.readAsString(), probe);
  });

  test('one unencodable box is isolated and visibly recorded', () async {
    await seedLegacyBoxes(invalidLayoutValue: true);
    final diagnostics = <(LegacyHiveMigrationDiagnostic, String)>[];

    final result = await migrator(
      diagnostics: (diagnostic, store) => diagnostics.add((diagnostic, store)),
    ).runIfNeeded();

    expect(result.failedStores, <String>['layouts']);
    expect(readData('layouts'), isEmpty);
    expect(readData('projects'), isNotEmpty);
    expect(readJson('migration')['failedStores'], <Object?>['layouts']);
    expect(diagnostics, <(LegacyHiveMigrationDiagnostic, String)>[
      (LegacyHiveMigrationDiagnostic.storeExportFailed, 'layouts'),
    ]);
    expect(File(p.join(legacyDirectory, 'layouts.hive')).existsSync(), isTrue);
  });

  test(
    'a marker-less interrupted run safely replays from legacy state',
    () async {
      await seedLegacyBoxes();
      await migrator().runIfNeeded();
      await File(
        p.join(stateDirectory, LegacyHiveMigrator.markerFileName),
      ).delete();
      await File(
        p.join(stateDirectory, 'projects.json'),
      ).writeAsString('{"version":1,"data":{"partial":true}}');

      final replay = await migrator().runIfNeeded();

      expect(replay.ran, isTrue);
      expect(readData('projects').containsKey('partial'), isFalse);
      expect(readData('projects')['__last_selected__'], 'project-1');
    },
  );

  test(
    'fresh install commits a no-source marker and creates stores lazily',
    () async {
      final result = await migrator(
        candidates: <String>[p.join(temporary.path, 'absent')],
      ).runIfNeeded();

      expect(result.ran, isTrue);
      expect(readJson('migration'), <String, Object?>{
        'version': 1,
        'source': 'none',
        'failedStores': <Object?>[],
      });
      for (final String name in LegacyHiveMigrator.storeNames) {
        expect(
          File(p.join(stateDirectory, '$name.json')).existsSync(),
          isFalse,
        );
      }
    },
  );
}

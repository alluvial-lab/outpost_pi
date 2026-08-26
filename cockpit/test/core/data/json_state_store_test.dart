import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/storage/json_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cockpit-json-store-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  File stateFile(String name) => File(p.join(temporary.path, '$name.json'));

  Map<String, dynamic> readEnvelope(String name) =>
      (jsonDecode(stateFile(name).readAsStringSync()) as Map<String, dynamic>);

  test('round-trips values and open is idempotent per factory', () async {
    final factory = JsonStateStoreFactory(temporary.path);
    final store = await factory.open('settings');

    expect(identical(store, await factory.open('settings')), isTrue);
    await store.put('theme', 'dark');
    await store.put('nested', <String, Object?>{
      'enabled': true,
      'sizes': <int>[1, 2],
    });
    await factory.flushAll();

    final reopened = await JsonStateStoreFactory(
      temporary.path,
    ).open('settings');
    expect(reopened.get('theme'), 'dark');
    expect(reopened.get('nested'), <String, Object?>{
      'enabled': true,
      'sizes': <int>[1, 2],
    });
    expect(reopened.keys.toSet(), <String>{'theme', 'nested'});
  });

  test(
    'concurrent opens share one store and flushAll flushes the shared instance',
    () async {
      final factory = JsonStateStoreFactory(temporary.path);
      final firstOpening = factory.open('concurrent');
      final secondOpening = factory.open('concurrent');
      final first = await firstOpening;
      final second = await secondOpening;

      expect(identical(first, second), isTrue);

      final pendingWrite = second.put('shared', true);
      await factory.flushAll();

      expect(stateFile('concurrent').existsSync(), isTrue);
      expect(readEnvelope('concurrent')['data'], <String, Object?>{
        'shared': true,
      });
      await pendingWrite;
    },
  );

  test('a failed open does not poison a later retry', () async {
    final file = stateFile('retry');
    await file.writeAsString('{not-json');
    var diagnosticCalls = 0;
    final factory = JsonStateStoreFactory(
      temporary.path,
      diagnostics: (_) {
        diagnosticCalls++;
        if (diagnosticCalls == 1) {
          throw StateError('diagnostic probe failed');
        }
      },
    );

    await expectLater(factory.open('retry'), throwsA(isA<StateError>()));
    final store = await factory.open('retry');

    expect(diagnosticCalls, 2);
    expect(store.keys, isEmpty);
    await store.put('recovered', true);
    await factory.flushAll();
    expect(readEnvelope('retry')['data'], <String, Object?>{'recovered': true});
  });

  test('coalesces a mutation burst into one attempted commit', () async {
    var writes = 0;
    final factory = JsonStateStoreFactory(
      temporary.path,
      atomicWriter: (File file, String contents) async {
        writes++;
        await JsonStateStore.writeAtomic(file, contents);
      },
    );
    final store = await factory.open('projects');

    final first = store.put('a', 1);
    final second = store.put('b', 2);
    final third = store.putAll(<String, Object?>{'c': 3, 'd': 4});
    await Future.wait<void>(<Future<void>>[first, second, third]);

    expect(writes, 1);
    expect(readEnvelope('projects')['data'], <String, Object?>{
      'a': 1,
      'b': 2,
      'c': 3,
      'd': 4,
    });
  });

  test('delete and multi-store flush persist complete envelopes', () async {
    final factory = JsonStateStoreFactory(temporary.path);
    final settings = await factory.open('settings');
    final projects = await factory.open('projects');

    unawaited(settings.put('remove-me', true));
    unawaited(settings.delete('remove-me'));
    unawaited(projects.put('project', <String, Object?>{'id': 'project'}));
    await factory.flushAll();

    expect(readEnvelope('settings'), <String, Object?>{
      'version': JsonStateStore.formatVersion,
      'data': <String, Object?>{},
    });
    expect(readEnvelope('projects')['data'], <String, Object?>{
      'project': <String, Object?>{'id': 'project'},
    });
  });

  test('serializes writes so an older snapshot cannot win', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var writes = 0;
    final factory = JsonStateStoreFactory(
      temporary.path,
      atomicWriter: (File file, String contents) async {
        writes++;
        if (writes == 1) {
          firstStarted.complete();
          await releaseFirst.future;
        }
        await JsonStateStore.writeAtomic(file, contents);
      },
    );
    final store = await factory.open('layouts');

    final oldAttempt = store.put('old', 1);
    final firstFlush = store.flush();
    await firstStarted.future;

    final newAttempt = store.put('new', 2);
    final secondFlush = store.flush();
    releaseFirst.complete();

    await Future.wait<void>(<Future<void>>[
      oldAttempt,
      firstFlush,
      newAttempt,
      secondFlush,
    ]);
    expect(writes, 2);
    expect(readEnvelope('layouts')['data'], <String, Object?>{
      'old': 1,
      'new': 2,
    });
  });

  test('atomic replacement leaves one complete file and no temp', () async {
    final file = stateFile('atomic');
    await JsonStateStore.writeAtomic(file, 'old');
    await JsonStateStore.writeAtomic(
      file,
      jsonEncode(<String, Object?>{
        'version': 1,
        'data': <String, Object?>{'complete': true},
      }),
    );

    expect(jsonDecode(await file.readAsString()), <String, Object?>{
      'version': 1,
      'data': <String, Object?>{'complete': true},
    });
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  for (final (name, contents, category)
      in <(String, String, JsonStateStoreDiagnostic)>[
        ('empty', '', JsonStateStoreDiagnostic.emptyFile),
        ('malformed', '{not-json', JsonStateStoreDiagnostic.malformedJson),
        ('envelope', '[1,2]', JsonStateStoreDiagnostic.invalidEnvelope),
        (
          'unsupported',
          '{"version":2,"data":{"keep":"me"}}',
          JsonStateStoreDiagnostic.unsupportedVersion,
        ),
      ]) {
    test(
      '$name state is quarantined, opens empty, and remains writable',
      () async {
        final file = stateFile(name);
        await file.writeAsString(contents);
        final diagnostics = <JsonStateStoreDiagnostic>[];
        final store = await JsonStateStoreFactory(
          temporary.path,
          diagnostics: diagnostics.add,
        ).open(name);

        expect(store.keys, isEmpty);
        expect(diagnostics, <JsonStateStoreDiagnostic>[category]);
        expect(File('${file.path}.corrupt').readAsStringSync(), contents);

        await store.put('recovered', true);
        await store.flush();
        expect(readEnvelope(name)['data'], <String, Object?>{
          'recovered': true,
        });
        expect(File('${file.path}.corrupt').readAsStringSync(), contents);
      },
    );
  }

  test('absent state opens empty without creating a file', () async {
    final store = await JsonStateStoreFactory(temporary.path).open('absent');

    expect(store.keys, isEmpty);
    expect(stateFile('absent').existsSync(), isFalse);
  });

  test('a failed write is reported rather than silently accepted', () async {
    final store = await JsonStateStoreFactory(
      temporary.path,
      atomicWriter: (_, _) async {
        throw const FileSystemException('write blocked');
      },
    ).open('settings');

    await expectLater(
      store.put('theme', 'dark'),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(store.flush(), throwsA(isA<FileSystemException>()));
  });

  test('rejects non-JSON values before mutating memory', () async {
    final store = await JsonStateStoreFactory(temporary.path).open('settings');

    expect(
      () => store.put('bad', DateTime(2026)),
      throwsA(isA<ArgumentError>()),
    );
    expect(store.get('bad'), isNull);
  });
}

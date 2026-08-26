import 'package:cockpit/app/cockpit/data/repositories/json_dismissed_update_store.dart';
import 'package:cockpit/app/cockpit/data/repositories/json_project_repository.dart';
import 'package:cockpit/app/cockpit/data/repositories/json_workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/core/data/repositories/json_settings_store.dart';
import 'package:cockpit/app/core/domain/contracts/state_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _MemoryStateStore memory;

  setUp(() {
    memory = _MemoryStateStore();
  });

  group('JsonSettingsStore', () {
    test(
      'returns defaults and round-trips the existing preference shape',
      () async {
        final store = JsonSettingsStore(memory);
        expect((await store.load()).themeMode, AppThemeMode.system);

        const settings = AppSettings(
          themeMode: AppThemeMode.dark,
          interfaceFont: 'Inter',
          interfaceSize: 16,
          codeFont: 'Mono',
          codeSize: 15,
          terminalFont: 'Terminal',
          syntaxTheme: SyntaxThemeId.dracula,
          pinUserMessage: false,
          lastOpenAppId: 'editor',
          lspCommands: <String, String>{'dart': 'dart language-server'},
          lspFormatters: <String, String>{'dart': 'dart format %FILE%'},
          formatOnSave: true,
          notificationsEnabled: false,
        );
        await store.save(settings);
        final loaded = await store.load();

        expect(loaded.themeMode, settings.themeMode);
        expect(loaded.interfaceFont, settings.interfaceFont);
        expect(loaded.interfaceSize, settings.interfaceSize);
        expect(loaded.codeFont, settings.codeFont);
        expect(loaded.codeSize, settings.codeSize);
        expect(loaded.terminalFont, settings.terminalFont);
        expect(loaded.syntaxTheme, settings.syntaxTheme);
        expect(loaded.pinUserMessage, settings.pinUserMessage);
        expect(loaded.lastOpenAppId, settings.lastOpenAppId);
        expect(loaded.lspCommands, settings.lspCommands);
        expect(loaded.lspFormatters, settings.lspFormatters);
        expect(loaded.formatOnSave, settings.formatOnSave);
        expect(loaded.notificationsEnabled, settings.notificationsEnabled);
        expect(memory.get('app'), settings.toJson());
      },
    );
  });

  group('JsonProjectRepository', () {
    test('preserves CRUD, manual order, and last selection', () async {
      final repository = JsonProjectRepository(memory);
      final later = Project(
        id: 'later',
        name: 'Later',
        path: '/workspace/later',
        colorValue: 0xFF010203,
        createdAt: DateTime.fromMillisecondsSinceEpoch(20),
        order: 1,
        imagePath: '/images/later.png',
      );
      final earlier = Project(
        id: 'earlier',
        name: 'Earlier',
        path: '/workspace/earlier',
        colorValue: 0xFF040506,
        createdAt: DateTime.fromMillisecondsSinceEpoch(10),
      );

      await repository.save(later);
      await repository.save(earlier);
      expect((await repository.all()).map((Project p) => p.id), <String>[
        'earlier',
        'later',
      ]);
      expect((await repository.all()).last.imagePath, '/images/later.png');

      await repository.saveLastSelected('later');
      expect(await repository.loadLastSelected(), 'later');
      await repository.saveLastSelected(null);
      expect(await repository.loadLastSelected(), isNull);

      await repository.remove('earlier');
      expect((await repository.all()).single.id, 'later');
    });

    test('ignores malformed records and keeps legacy field defaults', () async {
      await memory.put('missing-id', <String, Object?>{'path': '/missing'});
      await memory.put('missing-path', <String, Object?>{'id': 'missing'});
      await memory.put('legacy', <String, Object?>{
        'id': 'legacy',
        'path': '/workspace/legacy',
        'name': 42,
      });

      final projects = await JsonProjectRepository(memory).all();

      expect(projects, hasLength(1));
      expect(projects.single.id, 'legacy');
      expect(projects.single.name, '/workspace/legacy');
      expect(projects.single.colorValue, 0xFF2F6FF0);
      expect(projects.single.order, 0);
    });
  });

  group('JsonWorkspaceLayoutStore', () {
    test(
      'keeps encoded-string shape and treats corruption as missing',
      () async {
        final store = JsonWorkspaceLayoutStore(memory);
        final document = <String, dynamic>{
          'version': 1,
          'tree': <String, dynamic>{'kind': 'leaf'},
        };

        await store.save('project', document);
        expect(memory.get('project'), isA<String>());
        expect(await store.load('project'), document);

        await memory.put('project', '{malformed');
        expect(await store.load('project'), isNull);
        await memory.put('project', '[1,2]');
        expect(await store.load('project'), isNull);

        await store.remove('project');
        expect(await store.load('project'), isNull);
      },
    );
  });

  group('JsonDismissedUpdateStore', () {
    test(
      'preserves dismissed-version behavior in the settings store',
      () async {
        final store = JsonDismissedUpdateStore(memory);
        expect(store.dismissedVersion(), isNull);

        await store.dismiss('1.2.3');
        expect(store.dismissedVersion(), '1.2.3');

        await memory.put('dismissed_update_version', '');
        expect(store.dismissedVersion(), isNull);
      },
    );
  });
}

final class _MemoryStateStore implements StateStore {
  final Map<String, Object?> _data = <String, Object?>{};

  @override
  Object? get(String key) => _data[key];

  @override
  Iterable<String> get keys => _data.keys;

  @override
  Iterable<Object?> get values => _data.values;

  @override
  Future<void> put(String key, Object? value) async {
    _data[key] = value;
  }

  @override
  Future<void> putAll(Map<String, Object?> entries) async {
    _data.addAll(entries);
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> flush() async {}
}

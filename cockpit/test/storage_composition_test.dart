import 'package:cockpit/app/app_module.dart';
import 'package:cockpit/app/core/domain/contracts/state_store.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test(
    'app composition opens every repository through one state factory',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Cockpit',
        packageName: 'dev.outpostpi.cockpit',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      final factory = _RecordingStateStoreFactory();

      await buildAppModule(
        config: const PiSpawnConfig(executable: 'pi'),
        stateStores: factory,
      );

      expect(factory.openCalls, <String>['projects', 'layouts', 'settings']);
      expect(factory.stores.keys, <String>{'projects', 'layouts', 'settings'});
    },
  );
}

final class _RecordingStateStoreFactory implements StateStoreFactory {
  final List<String> openCalls = <String>[];
  final Map<String, StateStore> stores = <String, StateStore>{};

  @override
  Future<StateStore> open(String name) async {
    openCalls.add(name);
    return stores.putIfAbsent(name, _MemoryStateStore.new);
  }

  @override
  Future<void> flushAll() =>
      Future.wait<void>(stores.values.map((StateStore store) => store.flush()));
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

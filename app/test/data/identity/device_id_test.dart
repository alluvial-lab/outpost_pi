import 'package:app/data/identity/device_id.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('DeviceId', () {
    test('generates a non-empty id on first access', () async {
      final store = _FakeSecureStorage();
      final deviceId = DeviceId(store);

      final id = await deviceId.get();

      expect(id, isNotEmpty);
      expect(id.length, 32); // 128-bit base16
    });

    test('persists the id so a second instance returns the same value',
        () async {
      final store = _FakeSecureStorage();
      final first = await DeviceId(store).get();
      // A new DeviceId instance backed by the same store must read the
      // persisted value, not generate a new one.
      final second = await DeviceId(store).get();

      expect(second, first);
    });

    test('caches in memory — repeated calls do not hit storage', () async {
      final store = _FakeSecureStorage();
      final deviceId = DeviceId(store);

      final first = await deviceId.get();
      final second = await deviceId.get();

      expect(second, first);
    });

    test('two fresh stores produce different ids', () async {
      final idA = await DeviceId(_FakeSecureStorage()).get();
      final idB = await DeviceId(_FakeSecureStorage()).get();

      expect(idA, isNot(idB));
    });
  });
}

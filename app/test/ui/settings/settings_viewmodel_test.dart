import 'dart:async';
import 'dart:typed_data';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/settings/states/settings_state.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopTransport implements PeerTransport {
  @override
  Future<void> send(Uint8List data) async {}
  @override
  Future<Uint8List> receive() => Completer<Uint8List>().future;
  @override
  Future<void> close() async {}
}

PlainPeerChannel _channel() => PlainPeerChannel(transport: _NoopTransport());

ConnectionManager _conn({_FakeStorage? storage, ConnectionFactory? factory}) {
  return ConnectionManager(
    factory: factory ?? (_, _) async => _channel(),
    storage: storage ?? _FakeStorage([]),
  );
}

class _FakeStorage extends PairingStorage {
  List<PeerRecord> peers;
  var deleteCalls = 0;
  var silentDeleteCalls = 0;
  _FakeStorage(this.peers);

  @override
  Future<List<PeerRecord>> listPeers() async => List.of(peers);

  @override
  Future<void> savePeer(PeerRecord r) async {
    peers = [r, ...peers.where((p) => p.remoteEpk != r.remoteEpk)];
  }

  @override
  Future<void> deletePeer(String epk) async {
    deleteCalls += 1;
    peers = peers.where((p) => p.remoteEpk != epk).toList();
  }

  @override
  Future<void> deletePeerSilent(String epk) async {
    silentDeleteCalls += 1;
    peers = peers.where((p) => p.remoteEpk != epk).toList();
  }

  @override
  Future<List<PersistedRoom>> loadRooms(String remoteEpk) async => const [];
}

class _FakeDebugLog implements DebugLog {
  String? exportValue;
  var clearCount = 0;
  final List<DebugEvent> events = [];

  @override
  void log(DebugEvent event) => events.add(event);

  @override
  Future<String?> export() async => exportValue;

  @override
  Future<void> clear() async {
    clearCount += 1;
    exportValue = null;
  }

  @override
  void dispose() {}
}

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
  }) async => _store.remove(key);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PeerRecord _peerA() => const PeerRecord(
  remoteEpk: 'epk_A',
  sessionName: 'Pi A',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

void main() {
  group('SettingsViewModel', () {
    test('initial state is SettingsLoading', () {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      expect(vm.state, isA<SettingsLoading>());
      vm.dispose();
    });

    test('empty storage → SettingsNoPeer', () async {
      final storage = _FakeStorage([]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);
      expect(vm.state, isA<SettingsNoPeer>());
      vm.dispose();
    });

    test('peers loaded → SettingsList', () async {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      final s = vm.state as SettingsList;
      expect(s.peers.single.remoteEpk, 'epk_A');

      vm.dispose();
    });

    test(
      'revoke deletes peer + clears selectedPeerEpk if it matched',
      () async {
        final storage = _FakeStorage([_peerA()]);
        final prefs = Preferences(_FakeSecureStorage());
        await prefs.setSelectedPeerEpk('epk_A');

        final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
        await Future<void>.delayed(Duration.zero);

        await vm.revoke('epk_A');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(storage.peers, isEmpty);
        expect(storage.deleteCalls, 1);
        expect(storage.silentDeleteCalls, 0);
        expect(prefs.selectedPeerEpk, isNull);
        expect(vm.state, isA<SettingsNoPeer>());

        vm.dispose();
      },
    );

    test('revoke does NOT touch selectedPeerEpk if different', () async {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setSelectedPeerEpk('epk_other');

      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      await vm.revoke('epk_A');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(prefs.selectedPeerEpk, 'epk_other');

      vm.dispose();
    });

    test('setNickname updates state and storage', () async {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      await vm.setNickname('epk_A', 'Casa');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final s = vm.state as SettingsList;
      expect(s.peers.single.nickname, 'Casa');
      expect(storage.peers.single.nickname, 'Casa');

      vm.dispose();
    });

    test('setNickname with null clears the nickname', () async {
      final storage = _FakeStorage([_peerA().copyWith(nickname: 'Casa')]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      await vm.setNickname('epk_A', null);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect((vm.state as SettingsList).peers.single.nickname, isNull);
      expect(storage.peers.single.nickname, isNull);

      vm.dispose();
    });

    test('setNickname with whitespace clears the nickname', () async {
      final storage = _FakeStorage([_peerA().copyWith(nickname: 'Casa')]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      await vm.setNickname('epk_A', '   ');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect((vm.state as SettingsList).peers.single.nickname, isNull);

      vm.dispose();
    });

    test('setNickname is a no-op for unknown epk', () async {
      final storage = _FakeStorage([_peerA()]);
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(storage, prefs, _conn(storage: storage));
      await Future<void>.delayed(Duration.zero);

      await vm.setNickname('epk_does_not_exist', 'Casa');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(storage.peers.single.nickname, isNull);

      vm.dispose();
    });
  });

  group('SettingsViewModel — debug log', () {
    test('setDebugLogging persists the app-global toggle', () async {
      final store = _FakeSecureStorage();
      final prefs = Preferences(store);
      final vm = SettingsViewModel(_FakeStorage([]), prefs, _conn());
      await Future<void>.delayed(Duration.zero);

      expect(vm.isDebugLogging, isFalse);
      await vm.setDebugLogging(true);
      expect(vm.isDebugLogging, isTrue);
      expect(await store.read(key: 'prefs.debug_logging'), 'true');

      final reloaded = Preferences(store);
      await reloaded.load();
      expect(reloaded.debugLogging, isTrue);

      vm.dispose();
    });

    test(
      'export and clear delegate to DebugLog without changing toggle',
      () async {
        final prefs = Preferences(_FakeSecureStorage());
        await prefs.setDebugLogging(true);
        final debugLog = _FakeDebugLog()..exportValue = '{"tag":"msgSend"}';
        final vm = SettingsViewModel(
          _FakeStorage([]),
          prefs,
          _conn(),
          debugLog,
        );
        await Future<void>.delayed(Duration.zero);

        expect(await vm.exportDebugLog(), '{"tag":"msgSend"}');
        await vm.clearDebugLog();
        expect(debugLog.clearCount, 1);
        expect(prefs.debugLogging, isTrue);
        expect(vm.isDebugLogging, isTrue);

        vm.dispose();
      },
    );
  });

  group('SettingsViewModel — plan 14 relay config', () {
    test(
      'saveRelayUrl with valid URL persists override + returns null',
      () async {
        final prefs = Preferences(_FakeSecureStorage());
        final vm = SettingsViewModel(_FakeStorage([]), prefs, _conn());
        await Future<void>.delayed(Duration.zero);

        final err = await vm.saveRelayUrl('https://custom.example');
        expect(err, isNull);
        expect(prefs.relayUrl, 'https://custom.example');

        vm.dispose();
      },
    );

    test(
      'saveRelayUrl with invalid URL returns error and does NOT persist',
      () async {
        final prefs = Preferences(_FakeSecureStorage());
        final vm = SettingsViewModel(_FakeStorage([]), prefs, _conn());
        await Future<void>.delayed(Duration.zero);

        final err = await vm.saveRelayUrl('not-a-url');
        expect(err, isNotNull);
        expect(prefs.relayUrl, isNull);

        vm.dispose();
      },
    );

    test(
      'saveRelayUrl rejects ws:// / wss:// with the scheme-specific hint',
      () async {
        final prefs = Preferences(_FakeSecureStorage());
        final vm = SettingsViewModel(_FakeStorage([]), prefs, _conn());
        await Future<void>.delayed(Duration.zero);

        final err = await vm.saveRelayUrl('wss://relay.example');
        expect(err, isNotNull);
        expect(err, contains('ws://'));
        expect(err, contains('http://'));
        expect(prefs.relayUrl, isNull);

        vm.dispose();
      },
    );

    test('saveRelayUrl with empty / null is rejected (URL is now required) and '
        'does NOT clear the existing override', () async {
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setRelayUrl('https://x.example');
      final vm = SettingsViewModel(_FakeStorage([]), prefs, _conn());
      await Future<void>.delayed(Duration.zero);

      // Empty → error, override untouched.
      final emptyErr = await vm.saveRelayUrl('');
      expect(emptyErr, kRelayUrlInvalidGeneric);
      expect(prefs.relayUrl, 'https://x.example');

      // Whitespace-only → same (trimmed to empty).
      final blankErr = await vm.saveRelayUrl('   ');
      expect(blankErr, kRelayUrlInvalidGeneric);
      expect(prefs.relayUrl, 'https://x.example');

      // null → same.
      final nullErr = await vm.saveRelayUrl(null);
      expect(nullErr, kRelayUrlInvalidGeneric);
      expect(prefs.relayUrl, 'https://x.example');

      vm.dispose();
    });

    test('valid relay save reconnects after persistence', () async {
      final storage = _FakeStorage([_peerA()]);
      var connections = 0;
      final conn = _conn(
        storage: storage,
        factory: (_, _) async {
          connections += 1;
          return _channel();
        },
      );
      final prefs = Preferences(_FakeSecureStorage());
      final vm = SettingsViewModel(storage, prefs, conn);
      await Future<void>.delayed(Duration.zero);

      expect(await vm.saveRelayUrl('https://relay.example'), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(prefs.relayUrl, 'https://relay.example');
      expect(connections, 1);
      vm.dispose();
      conn.dispose();
    });

    test(
      'unconfigured relay stays blank and exposes a recovery label',
      () async {
        final prefs = Preferences(_FakeSecureStorage());
        final vm = SettingsViewModel(_FakeStorage([]), prefs, _conn());
        await Future<void>.delayed(Duration.zero);

        expect(vm.relayResolution, isA<UnconfiguredRelay>());
        expect(vm.relayUrlOverride, isEmpty);
        expect(vm.effectiveRelayLabel, 'Not configured');

        final err = await vm.saveRelayUrl('https://relay.example');
        expect(err, isNull);
        expect(vm.relayResolution, isA<ConfiguredRelay>());
        expect(vm.relayUrlOverride, 'https://relay.example');
        expect(prefs.relayUrl, 'https://relay.example');

        vm.dispose();
      },
    );
  });
}

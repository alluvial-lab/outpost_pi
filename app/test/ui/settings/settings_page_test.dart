import 'dart:async';
import 'dart:typed_data';

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/settings/settings_page.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _NoopTransport implements PeerTransport {
  @override
  Future<void> send(Uint8List data) async {}

  @override
  Future<Uint8List> receive() => Completer<Uint8List>().future;

  @override
  Future<void> close() async {}
}

PlainPeerChannel _channel() => PlainPeerChannel(transport: _NoopTransport());

ConnectionManager _conn({_FakeStorage? storage}) {
  return ConnectionManager(
    factory: (_, _) async => _channel(),
    storage: storage ?? _FakeStorage([]),
  );
}

class _FakeStorage extends PairingStorage {
  List<PeerRecord> peers;
  _FakeStorage(this.peers);

  @override
  Future<List<PeerRecord>> listPeers() async => List.of(peers);
}

class _FakeDebugLog implements DebugLog {
  String? exportValue;
  var clearCount = 0;

  @override
  void log(DebugEvent event) {}

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

Future<({Preferences prefs, SettingsViewModel vm, ConnectionManager conn})>
_pumpSettings(
  WidgetTester tester, {
  required _FakeSecureStorage store,
  required _FakeDebugLog debugLog,
  Future<void> Function(String jsonl)? share,
}) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final prefs = Preferences(store);
  await prefs.load();
  final storage = _FakeStorage([]);
  final conn = _conn(storage: storage);
  final vm = SettingsViewModel(storage, prefs, conn, null, debugLog);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<Preferences>.value(value: prefs),
        ChangeNotifierProvider<SettingsViewModel>.value(value: vm),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        home: SettingsPage(shareDebugLogFn: share ?? (_) async {}),
      ),
    ),
  );
  await tester.pump();
  return (prefs: prefs, vm: vm, conn: conn);
}

void main() {
  testWidgets('debug logging switch persists across re-instantiated prefs', (
    tester,
  ) async {
    final store = _FakeSecureStorage();
    final debugLog = _FakeDebugLog();
    final result = await _pumpSettings(
      tester,
      store: store,
      debugLog: debugLog,
    );

    expect(result.prefs.debugLogging, isFalse);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Debug logging'),
          )
          .value,
      isFalse,
    );

    await tester.tap(find.widgetWithText(SwitchListTile, 'Debug logging'));
    await tester.pump();

    expect(result.prefs.debugLogging, isTrue);
    expect(await store.read(key: 'prefs.debug_logging'), 'true');

    final reloaded = Preferences(store);
    await reloaded.load();
    expect(reloaded.debugLogging, isTrue);

    result.vm.dispose();
    result.conn.dispose();
  });

  testWidgets('Export debug log opens the share sheet with jsonl content', (
    tester,
  ) async {
    final store = _FakeSecureStorage();
    final debugLog = _FakeDebugLog()
      ..exportValue = '{"tag":"msgSend","id":"msg-1"}';
    String? shared;

    final result = await _pumpSettings(
      tester,
      store: store,
      debugLog: debugLog,
      share: (jsonl) async => shared = jsonl,
    );

    await tester.scrollUntilVisible(
      find.text('Export debug log'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    final exportButton = find.widgetWithText(
      OutlinedButton,
      'Export debug log',
    );
    await tester.tap(exportButton);
    await tester.pumpAndSettle();

    expect(shared, '{"tag":"msgSend","id":"msg-1"}');
    expect(find.text('Debug log export opened'), findsOneWidget);
    result.vm.dispose();
    result.conn.dispose();
  });

  testWidgets(
    'Export debug log shows no-log feedback when export returns null',
    (tester) async {
      final result = await _pumpSettings(
        tester,
        store: _FakeSecureStorage(),
        debugLog: _FakeDebugLog(),
      );

      await tester.scrollUntilVisible(
        find.text('Export debug log'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      final exportButton = find.widgetWithText(
        OutlinedButton,
        'Export debug log',
      );
      await tester.tap(exportButton);
      await tester.pumpAndSettle();

      expect(find.text('No debug log yet'), findsOneWidget);
      result.vm.dispose();
      result.conn.dispose();
    },
  );

  testWidgets('Clear debug log confirms, wipes, and preserves the toggle', (
    tester,
  ) async {
    final store = _FakeSecureStorage();
    final prefs = Preferences(store);
    await prefs.setDebugLogging(true);
    final debugLog = _FakeDebugLog()
      ..exportValue = '{"tag":"msgEcho","id":"msg-1"}';

    final result = await _pumpSettings(
      tester,
      store: store,
      debugLog: debugLog,
    );
    expect(result.prefs.debugLogging, isTrue);

    await tester.scrollUntilVisible(
      find.text('Clear debug log'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    final clearButton = find.widgetWithText(OutlinedButton, 'Clear debug log');
    await tester.tap(clearButton);
    await tester.pumpAndSettle();
    expect(find.text('Clear debug log?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Clear debug log'));
    await tester.pumpAndSettle();

    expect(debugLog.clearCount, 1);
    expect(result.prefs.debugLogging, isTrue);
    expect(await store.read(key: 'prefs.debug_logging'), 'true');
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Debug logging'),
          )
          .value,
      isTrue,
    );
    expect(find.text('Debug log cleared'), findsOneWidget);

    result.vm.dispose();
    result.conn.dispose();
  });
}

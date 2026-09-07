// Fleet settings section widget tests.
//
// Builds the real SettingsPage over a live fake-channel ConnectionManager
// (the settings_page_test scaffolding) plus the real FleetUpdateViewModel,
// covering the confirmation gate, disabled-with-reason, and phase + per-Pi
// ack rendering.

import 'dart:async';
import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/settings/fleet_update_viewmodel.dart';
import 'package:app/ui/settings/settings_page.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakeChannel implements IChannel, IControlLink {
  final _ctrl = StreamController<ServerMessage>.broadcast();
  final _controlCtrl = StreamController<ControlInbound>.broadcast();
  final List<ClientMessage> sent = [];

  @override
  Stream<ServerMessage> get serverMessages => _ctrl.stream;

  @override
  Stream<ControlInbound> get controlFrames => _controlCtrl.stream;

  @override
  Future<void> send(ClientMessage msg) async {
    sent.add(msg);
  }

  @override
  void sendControl(Map<String, dynamic> json) {}

  @override
  Future<void> close() async {
    await _ctrl.close();
    await _controlCtrl.close();
  }

  void push(ServerMessage m) => _ctrl.add(m);
}

class _FakeStorage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => const [];
}

class _FakeDebugLog implements DebugLog {
  @override
  void log(DebugEvent event) {}

  @override
  Future<String?> export() async => null;

  @override
  Future<void> clear() async {}

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
  }) async {
    _store.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.from(_store);

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.clear();

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _peer = PeerRecord(
  remoteEpk: 'epk_fleet_widget',
  sessionName: 'pi',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

class _Harness {
  final ConnectionManager cm;
  final FleetUpdateViewModel vm;
  final _FakeChannel channel;
  bool _disposed = false;

  _Harness(this.cm, this.vm, this.channel);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // The ViewModel must release channel listeners before the manager closes
    // the channel and its stream controllers.
    vm.dispose();
    cm.dispose();
  }
}

Future<_Harness> _pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final store = _FakeSecureStorage();
  final prefs = Preferences(store);
  await prefs.load();
  final conn = ConnectionManager(
    factory: (_, _) async => _FakeChannel(),
    storage: _FakeStorage(),
  );
  final settingsVm = SettingsViewModel(
    _FakeStorage(),
    prefs,
    conn,
    _FakeDebugLog(),
  );
  final channel = _FakeChannel();
  final fleetVm = FleetUpdateViewModel(
    conn,
    // The widget only needs the send path; the production repository is
    // exercised by the viewmodel tests, so a thin inline stub keeps this
    // suite focused on widget behavior.
    _StubActionsRepository(channel),
    recoveryTimeout: const Duration(minutes: 5),
    requestTimeout: const Duration(seconds: 15),
  );
  final harness = _Harness(conn, fleetVm, channel);
  addTearDown(harness.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<Preferences>.value(value: prefs),
        ChangeNotifierProvider<SettingsViewModel>.value(value: settingsVm),
        ChangeNotifierProvider<FleetUpdateViewModel>.value(value: fleetVm),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        home: const SettingsPage(shareDebugLogFn: _shareNoop),
      ),
    ),
  );
  await tester.pump();
  return harness;
}

Future<void> _shareNoop(String jsonl) async {}

/// Sends through the fake channel so the section under test drives the
/// real request path shape.
class _StubActionsRepository implements IActionsRepository {
  final _FakeChannel channel;
  _StubActionsRepository(this.channel);

  @override
  ActiveRoomMeta get activeRoomMeta => const ActiveRoomMeta();

  @override
  Stream<ActiveRoomMeta> get activeRoomMetaStream =>
      const Stream<ActiveRoomMeta>.empty();

  @override
  Future<void> compact() async {}

  @override
  Future<String> fleetUpdate() async {
    final id = 'act_widget_fleet';
    await channel.send(FleetUpdate(id: id, sessionId: 'session-widget'));
    return id;
  }

  @override
  Future<ModelsCatalogue> listModels({bool forceRefresh = false}) async {
    return const ModelsCatalogue(models: [], current: null);
  }

  @override
  Future<void> newSession() async {}

  @override
  Future<void> setModel(String provider, String modelId) async {}

  @override
  Future<void> setThinking(ThinkingLevel level) async {}

  @override
  void dispose() {}
}

Future<void> _connectRoom(WidgetTester tester, _Harness h) async {
  final online = h.cm.statusStream
      .where((s) => s is StatusOnline)
      .first
      .timeout(const Duration(seconds: 1));
  h.cm.adopt(h.channel, _peer);
  await online;
  h.channel.push(
    PairOk(
      inReplyTo: 'pair-widget',
      sessionName: 'pi',
      sessionStartedAt: DateTime.utc(2026).millisecondsSinceEpoch,
      roomId: 'main',
      sessionId: 'session-widget',
    ),
  );
  // Widget tests run under FakeAsync; pump the broadcast delivery rather
  // than awaiting a zero-duration Timer, which never advances on its own.
  await tester.pump();
}

Future<void> _scrollToFleet(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('fleet-update-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('button is disabled with a reason when no room is connected', (
    tester,
  ) async {
    final h = await _pumpSettings(tester);
    await _scrollToFleet(tester);

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('fleet-update-button')),
    );
    expect(
      button.onPressed,
      isNull,
      reason: 'no paired/connected room must block the action',
    );
    expect(
      find.byKey(const Key('fleet-update-blocked-reason')),
      findsOneWidget,
    );
    expect(h.channel.sent.whereType<FleetUpdate>(), isEmpty);
    h.dispose();
  });

  testWidgets('confirmation dialog gates the send; cancel sends nothing', (
    tester,
  ) async {
    final h = await _pumpSettings(tester);
    await _connectRoom(tester, h);
    await _scrollToFleet(tester);

    await tester.tap(find.byKey(const Key('fleet-update-button')));
    await tester.pumpAndSettle();

    expect(find.text('Update + restart the fleet?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fleet-update-cancel')));
    await tester.pumpAndSettle();
    expect(h.channel.sent.whereType<FleetUpdate>(), isEmpty);
    expect(h.vm.state, isA<FleetIdle>());
    h.dispose();
  });

  testWidgets('confirming the dialog sends the fleet_update request', (
    tester,
  ) async {
    final h = await _pumpSettings(tester);
    await _connectRoom(tester, h);
    await _scrollToFleet(tester);

    await tester.tap(find.byKey(const Key('fleet-update-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fleet-update-confirm')));
    await tester.pump();

    expect(h.channel.sent.whereType<FleetUpdate>(), hasLength(1));
    h.dispose();
  });

  testWidgets('arming phase renders progress and the per-Pi ack list', (
    tester,
  ) async {
    final h = await _pumpSettings(tester);
    await _connectRoom(tester, h);
    await _scrollToFleet(tester);

    h.channel.push(
      const FleetUpdateStatus(
        updateId: 'u1',
        phase: 'arming',
        peers: [
          {'peer': '/vm@a', 'state': 'armed'},
          {'peer': '/vm@b', 'state': 'deferred', 'reason': 'turn active'},
          {'peer': '/vm@c', 'state': 'no-ack'},
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fleet-update-status')), findsOneWidget);
    expect(
      find.textContaining('Arming fleet restart — 1/3 Pis armed.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('fleet-update-ack-/vm@a')), findsOneWidget);
    expect(find.text('/vm@b — deferred (turn active)'), findsOneWidget);
    expect(find.text('/vm@c — no-ack'), findsOneWidget);
    h.dispose();
  });

  testWidgets('failure phase renders the detail', (tester) async {
    final h = await _pumpSettings(tester);
    await _connectRoom(tester, h);
    await _scrollToFleet(tester);

    h.channel.push(
      const FleetUpdateStatus(
        updateId: 'u1',
        phase: 'update_failed',
        detail: 'npm ERR! network',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Update failed: npm ERR! network'),
      findsOneWidget,
    );
    h.dispose();
  });
}

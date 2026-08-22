@Tags(['e2e'])
library;

import 'dart:io';

import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'support/live_device_harness.dart';

const _phase = String.fromEnvironment('E2E_LIVE_PHASE');
const _skipColdReplayDuplicates = false;
const _baselinePrompt = 'deterministic grid baseline prompt';
const _baselineReply = 'deterministic grid baseline reply';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'deterministic pairing hydration and mid-turn fault grid',
    (tester) async {
      final harness = await LiveDeviceHarness.create(restorePair: false);
      var cell = 0;
      try {
        await _cell(
          harness,
          index: cell++,
          moment: 'qr_scan',
          fault: 'relay_pause',
          body: () => _pairAfterVisibleQrFailure(tester, harness),
        );
        await harness.mountChat(tester);
        await harness.sendAndResolve(
          tester,
          prompt: _baselinePrompt,
          reply: _baselineReply,
        );

        await _cell(
          harness,
          index: cell++,
          moment: 'pairing_handshake',
          fault: 'latency',
          body: () => _rePairUnderFault(
            tester,
            harness,
            command: 'net_fault latency 250',
          ),
        );
        await _cell(
          harness,
          index: cell++,
          moment: 'pairing_handshake',
          fault: 'bandwidth',
          body: () => _rePairUnderFault(
            tester,
            harness,
            command: 'net_fault bandwidth 64',
          ),
        );

        await _cell(
          harness,
          index: cell++,
          moment: 'hydration_window',
          fault: 'down',
          body: () => _hydrateUnderFault(
            tester,
            harness,
            command: 'net_fault down',
            restoreWhileConnecting: true,
          ),
        );
        await _cell(
          harness,
          index: cell++,
          moment: 'hydration_window',
          fault: 'compound',
          body: () => _hydrateUnderFault(
            tester,
            harness,
            command: 'net_compound latency=200 bandwidth=64',
          ),
        );
        await _cell(
          harness,
          index: cell++,
          moment: 'hydration_window',
          fault: 'relay_kill',
          body: () => _hydrateUnderFault(
            tester,
            harness,
            command: 'relay_kill',
            clearCommand: null,
          ),
        );
        await _cell(
          harness,
          index: cell++,
          moment: 'hydration_window',
          fault: 'slow_close',
          body: () => _hydrateUnderFault(
            tester,
            harness,
            command: 'net_fault slow_close 750',
          ),
        );

        await _cell(
          harness,
          index: cell++,
          moment: 'mid_turn_staged',
          fault: 'timeout',
          body: () => _stagedTurnUnderFault(
            tester,
            harness,
            fault: 'net_fault timeout 4000',
            suffix: 'timeout',
          ),
        );
        await _cell(
          harness,
          index: cell++,
          moment: 'mid_turn_staged',
          fault: 'slicer',
          body: () => _stagedTurnUnderFault(
            tester,
            harness,
            fault: 'net_fault slicer 250',
            suffix: 'slicer',
          ),
        );

        expect(cell, 9);
        expect(harness.preferences.selectedRoomRaw, isNotNull);
        expect(
          harness.connection.isRoomWorking(
            harness.peer.remoteEpk,
            harness.connection.activeRoomId,
          ),
          isFalse,
        );
      } finally {
        requestLiveFault('net_clear');
        await harness.close(tester);
      }
    },
    skip: _phase.isNotEmpty && _phase != 'grid-main',
    timeout: const Timeout(Duration(minutes: 10)),
  );

  // Regression cells for durable cold replay admission. Each cold cell keeps
  // the exact-one transcript assertion in _mountAndAssertBaseline.
  testWidgets(
    'cold-open pi restart preserves one transcript projection',
    (tester) => _runColdCell(
      tester,
      index: 9,
      fault: 'pi_restart',
      body: _coldOpenAfterPiRestart,
    ),
    skip: _phase != 'grid-cold' || _skipColdReplayDuplicates,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'cold-open background cycle preserves one transcript projection',
    (tester) => _runColdCell(
      tester,
      index: 10,
      fault: 'app_background',
      body: _coldOpenAfterBackground,
    ),
    skip: _phase != 'grid-cold' || _skipColdReplayDuplicates,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'cold-open airplane cycle preserves one transcript projection',
    (tester) => _runColdCell(
      tester,
      index: 11,
      fault: 'app_airplane',
      body: _coldOpenAfterAirplane,
    ),
    skip: _phase != 'grid-cold' || _skipColdReplayDuplicates,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

typedef _ColdCellBody =
    Future<void> Function(WidgetTester tester, LiveDeviceHarness harness);

Future<void> _runColdCell(
  WidgetTester tester, {
  required int index,
  required String fault,
  required _ColdCellBody body,
}) async {
  final harness = await LiveDeviceHarness.create(restorePair: true);
  try {
    await _cell(
      harness,
      index: index,
      moment: 'cold_open',
      fault: fault,
      body: () => body(tester, harness),
    );
  } finally {
    requestLiveFault('app_airplane off');
    requestLiveFault('net_clear');
    await harness.close(tester);
  }
}

Future<void> _cell(
  LiveDeviceHarness harness, {
  required int index,
  required String moment,
  required String fault,
  required Future<void> Function() body,
}) async {
  harness.debugLog.log(
    WsInEvent(
      ts: DateTime.now(),
      count: index,
      kind: 'grid-cell-start',
      stage: '$moment/$fault',
    ),
  );
  await body();
  harness.debugLog.log(
    WsInEvent(
      ts: DateTime.now(),
      count: index,
      kind: 'grid-cell-pass',
      stage: '$moment/$fault',
    ),
  );
  debugPrintSynchronously('GRID_CELL_PASS $index $moment/$fault');
}

Future<void> _pairAfterVisibleQrFailure(
  WidgetTester tester,
  LiveDeviceHarness harness,
) async {
  final firstUri = await harness.issuePairCode(tester);
  requestLiveFault('relay_pause');
  await eventually<bool>(
    tester,
    () async => await liveRelayHealthReachable() ? null : true,
    description: 'QR-scan relay pause visible at the app boundary',
  );
  final error = await harness.pairFailureFromUri(tester, firstUri);
  expect(error, isNotEmpty);

  requestLiveFault('relay_resume');
  await eventually<bool>(
    tester,
    () async => await liveRelayHealthReachable() ? true : null,
    description: 'relay resumed after QR-scan cell',
  );
  await harness.retryPairFromUri(tester, await harness.issuePairCode(tester));
}

Future<void> _rePairUnderFault(
  WidgetTester tester,
  LiveDeviceHarness harness, {
  required String command,
}) async {
  await harness.unmountChat(tester);
  harness.pairingViewModel.retry();
  final uri = await harness.issuePairCode(tester);
  requestLiveFault(command);
  await tester.pump(const Duration(seconds: 1));
  try {
    await harness.pairFromUri(tester, uri);
  } finally {
    requestLiveFault('net_clear');
  }
  await harness.mountChat(tester);
  await eventually<bool>(
    tester,
    () async => find.text(_baselineReply).evaluate().isNotEmpty ? true : null,
    description: 'baseline transcript after faulted re-pair',
  );
}

Future<void> _hydrateUnderFault(
  WidgetTester tester,
  LiveDeviceHarness harness, {
  required String command,
  String? clearCommand = 'net_clear',
  bool restoreWhileConnecting = false,
}) async {
  final room = harness.connection.activeRoomId;
  final selection = harness.preferences.selectedRoomRaw;
  await harness.connection.disconnect();
  requestLiveFault(command);
  await tester.pump(const Duration(seconds: 1));
  if (restoreWhileConnecting && clearCommand != null) {
    await eventually<bool>(
      tester,
      () async => await liveRelayHealthReachable() ? null : true,
      description: 'hard-down hydration boundary is unavailable',
    );
    requestLiveFault(clearCommand);
    await eventually<bool>(
      tester,
      () async => await liveRelayHealthReachable() ? true : null,
      description: 'hard-down hydration boundary restored',
    );
  }
  try {
    await harness.connection.connectTo(harness.peer);
  } finally {
    if (clearCommand != null) requestLiveFault(clearCommand);
  }
  await harness.waitOnlineAndLive(tester: tester);
  expect(harness.connection.activeRoomId, room);
  expect(harness.preferences.selectedRoomRaw, selection);
  expect(find.text(_baselineReply), findsOneWidget);
}

Future<void> _stagedTurnUnderFault(
  WidgetTester tester,
  LiveDeviceHarness harness, {
  required String fault,
  required String suffix,
}) async {
  final prompt = 'grid staged $suffix prompt';
  final reply = 'grid staged $suffix reply';
  await harness.host.post('/turn-control/defer-next', <String, Object>{
    'reply': reply,
  });
  await harness.sync.sendMessage(prompt);
  await eventually<Map<String, dynamic>>(tester, () async {
    final value = await harness.host.tryGet('/turn-control');
    return value?['phase'] == 'pending' ? value : null;
  }, description: '$suffix staged turn pending');
  await harness.waitForSubmissionVisibility(tester, prompt);

  requestLiveFault(fault);
  await tester.pump(const Duration(seconds: 1));
  await harness.host.post('/turn-control/resolve', const <String, Object>{});
  await tester.pump(const Duration(seconds: 2));
  await harness.connection.disconnect();
  requestLiveFault('net_clear');
  await harness.connection.connectTo(harness.peer);
  await harness.waitOnlineAndLive(tester: tester);
  await eventually<bool>(
    tester,
    () async => find.text(reply).evaluate().isNotEmpty ? true : null,
    description: '$suffix reply recovered through replay',
  );
  await eventually<bool>(
    tester,
    () async =>
        harness.connection.isRoomWorking(
          harness.peer.remoteEpk,
          harness.connection.activeRoomId,
        )
        ? null
        : true,
    description: '$suffix working=false convergence',
  );
}

Future<void> _coldOpenAfterPiRestart(
  WidgetTester tester,
  LiveDeviceHarness harness,
) async {
  final before = await harness.host.get('/status');
  requestLiveFault('pi_restart');
  await eventually<Map<String, dynamic>>(
    tester,
    () async {
      final value = await harness.host.tryGet('/status');
      return value != null &&
              value['generation'] != before['generation'] &&
              value['relayConnected'] == true
          ? value
          : null;
    },
    description: 'Pi restart before cold direct route',
    timeout: const Duration(seconds: 45),
  );
  await harness.waitOnlineAndLive(tester: tester);
  await _mountAndAssertBaseline(tester, harness);
}

Future<void> _coldOpenAfterBackground(
  WidgetTester tester,
  LiveDeviceHarness harness,
) async {
  await harness.unmountChat(tester);
  requestLiveFault('app_background');
  await Future<void>.delayed(const Duration(seconds: 2));
  requestLiveFault('app_foreground');
  await Future<void>.delayed(const Duration(seconds: 1));
  await _mountAndAssertBaseline(tester, harness);
}

Future<void> _coldOpenAfterAirplane(
  WidgetTester tester,
  LiveDeviceHarness harness,
) async {
  await harness.unmountChat(tester);
  requestLiveFault('app_airplane on');
  await _waitAirplaneAck(tester, 'on');
  await eventually<bool>(
    tester,
    () async => harness.connection.status is! StatusOnline ? true : null,
    description: 'airplane cold-open disconnect',
    timeout: const Duration(seconds: 45),
  );
  requestLiveFault('app_airplane off');
  await _waitAirplaneAck(tester, 'off');
  await harness.waitOnlineAndLive(tester: tester);
  await _mountAndAssertBaseline(tester, harness);
}

Future<void> _mountAndAssertBaseline(
  WidgetTester tester,
  LiveDeviceHarness harness,
) async {
  await harness.mountChat(tester);
  await eventually<bool>(
    tester,
    () async => find.text(_baselineReply).evaluate().isNotEmpty ? true : null,
    description: 'persisted baseline on direct cold route',
  );
  expect(find.text(_baselinePrompt), findsOneWidget);
  expect(find.text(_baselineReply), findsOneWidget);
}

Future<void> _waitAirplaneAck(WidgetTester tester, String expected) async {
  final docs = await getApplicationDocumentsDirectory();
  final ack = File('${docs.path}/.outpost_live_airplane');
  await eventually<bool>(tester, () async {
    try {
      return (await ack.readAsString()).trim() == expected ? true : null;
    } catch (_) {
      return null;
    }
  }, description: 'airplane mode $expected acknowledgement');
}

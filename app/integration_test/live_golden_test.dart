@Tags(['e2e'])
library;

import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/live_device_harness.dart';

const _phase = String.fromEnvironment('E2E_LIVE_PHASE');
const _firstPrompt = 'golden prompt from the phone';
const _firstReply = 'golden staged assistant reply';
const _reconnectPrompt = 'golden prompt after reconnect';
const _reconnectReply = 'golden reply after reconnect';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Invariant 3: a paired turn renders both bubbles and working returns idle.
  testWidgets(
    'pair, send, staged reply, and working convergence render on device',
    (tester) async {
      final harness = await LiveDeviceHarness.create(restorePair: false);
      try {
        await harness.pair(tester);
        await harness.mountChat(tester);
        await harness.sendAndResolve(
          tester,
          prompt: _firstPrompt,
          reply: _firstReply,
        );

        expect(find.text(_firstPrompt), findsOneWidget);
        expect(find.text(_firstReply), findsOneWidget);
        final rows = await harness.transcriptRows();
        expect(
          rows,
          contains(
            isA<MessageRecord>()
                .having((row) => row.role, 'role', MsgRole.assistant)
                .having((row) => row.text, 'text', _firstReply),
          ),
        );
      } finally {
        await harness.close(tester);
      }
    },
    skip: _phase.isNotEmpty && _phase != 'pair-chat',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  /// Invariant 2: a cold direct session route renders persisted history.
  testWidgets(
    'cold app process opens the session route with hydrated history',
    (tester) async {
      final harness = await LiveDeviceHarness.create(restorePair: true);
      try {
        await harness.mountChat(tester);
        await eventually<bool>(
          tester,
          () async =>
              find.text(_firstReply).evaluate().isNotEmpty ? true : null,
          description: 'persisted assistant history on direct route',
        );
        expect(find.text(_firstPrompt), findsOneWidget);
        expect(find.text(_firstReply), findsOneWidget);

        final routeEvents = (await harness.captureEvents()).where(
          (event) => event['tag'] == 'route',
        );
        expect(
          routeEvents.any((event) => event['phase'] == 'projection-ready'),
          isTrue,
        );
      } finally {
        await harness.close(tester);
      }
    },
    skip: _phase.isNotEmpty && _phase != 'cold-open',
    timeout: const Timeout(Duration(minutes: 4)),
  );

  /// Invariant 3: timeout recovery keeps the selected room and chat usable.
  testWidgets(
    'mid-conversation timeout clears and recovers without user action',
    (tester) async {
      final harness = await LiveDeviceHarness.create(restorePair: true);
      try {
        await harness.mountChat(tester);
        await eventually<bool>(
          tester,
          () async =>
              find.text(_firstReply).evaluate().isNotEmpty ? true : null,
          description: 'pre-fault conversation render',
        );
        final selectedRoom = harness.preferences.selectedRoomRaw;

        requestLiveFault('net_fault timeout 8000');
        await eventually<bool>(
          tester,
          () async => await liveRelayHealthReachable() ? null : true,
          description: 'timeout toxic visible at app relay boundary',
          timeout: const Duration(seconds: 20),
        );
        await eventually<bool>(
          tester,
          () async => harness.connection.status is! StatusOnline ? true : null,
          description: 'connection leaves online under timeout',
          timeout: const Duration(seconds: 45),
        );

        requestLiveFault('net_clear');
        await eventually<bool>(
          tester,
          () async => await liveRelayHealthReachable() ? true : null,
          description: 'relay boundary restored',
        );
        await harness.waitOnlineAndLive(tester: tester);
        expect(harness.preferences.selectedRoomRaw, selectedRoom);

        await harness.sendAndResolve(
          tester,
          prompt: _reconnectPrompt,
          reply: _reconnectReply,
        );
        expect(find.text(_firstReply), findsOneWidget);
        expect(find.text(_reconnectReply), findsOneWidget);
      } finally {
        await harness.close(tester);
      }
    },
    skip: _phase.isNotEmpty && _phase != 'reconnect',
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

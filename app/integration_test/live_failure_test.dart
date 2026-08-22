@Tags(['e2e'])
library;

import 'dart:io';

import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/session_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'support/live_device_harness.dart';

const _phase = String.fromEnvironment('E2E_LIVE_PHASE');
const _skipBlankChatKnownBug = true;
const _swallowPrompt = 'identity-window message must stay visible';
const _offlinePrompt = 'offline message held for resend';
const _beforeRestartPrompt = 'message before extension restart';
const _beforeRestartReply = 'reply before extension restart';
const _afterRestartPrompt = 'message after extension restart';
const _afterRestartReply = 'reply after extension restart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Invariant 1: a send in the reconnect identity window is never absent.
  testWidgets(
    'reconnect identity window keeps an immediate send visible',
    (tester) async {
      final harness = await LiveDeviceHarness.create(restorePair: false);
      try {
        await harness.pair(tester);
        await harness.mountChat(tester);
        requestLiveFault('net_fault down');
        await eventually<bool>(
          tester,
          () async => harness.connection.status is! StatusOnline ? true : null,
          description: 'forced reconnect edge',
        );
        requestLiveFault('net_clear');
        await eventually<bool>(
          tester,
          () async => harness.connection.status is StatusOnline ? true : null,
          description: 'relay reconnect before fresh room hydration',
        );

        await harness.sync.sendMessage(_swallowPrompt);
        await harness.waitForSubmissionVisibility(tester, _swallowPrompt);
      } finally {
        await harness.close(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  /// Invariant 2: a direct cold chat route never hides persisted history.
  // The fix story flips _skipBlankChatKnownBug; keep the phase gate and
  // hydrate assertion intact for backlog-app-blank-chat-direct-open.
  testWidgets(
    'cold direct-open chat renders existing transcript history',
    (tester) async {
      final harness = await LiveDeviceHarness.create(restorePair: true);
      try {
        // run-live.sh force-stops the preceding failure-main process before
        // launching this phase. mountChat is therefore the first/direct route
        // in a fresh app process, backed by the transcript persisted in main.
        await harness.mountChat(tester);
        await eventually<bool>(
          tester,
          () async => find.text(_beforeRestartReply).evaluate().isNotEmpty
              ? true
              : null,
          description: 'persisted history on direct cold process route',
        );
        expect(find.text(_beforeRestartPrompt), findsOneWidget);
        expect(find.text(_beforeRestartReply), findsOneWidget);
      } finally {
        await harness.close(tester);
      }
    },
    skip: _phase != 'blank-cold' || _skipBlankChatKnownBug,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  /// Invariant 1: an offline send is pending, resent, then visibly terminal.
  testWidgets(
    'offline send remains visible and resends after airplane recovery',
    (tester) async {
      final harness = await LiveDeviceHarness.create(restorePair: false);
      try {
        await harness.pair(tester);
        await harness.mountChat(tester);
        requestLiveFault('app_airplane on');
        await _waitAirplaneAck(tester, 'on');
        await eventually<bool>(
          tester,
          () async => harness.connection.status is! StatusOnline ? true : null,
          description: 'airplane mode disconnect',
          timeout: const Duration(seconds: 45),
        );

        await harness.sync.sendMessage(_offlinePrompt);
        await eventually<bool>(
          tester,
          () async =>
              find.text(_offlinePrompt).evaluate().isNotEmpty ? true : null,
          description: 'visible held pending bubble',
        );
        expect(find.text('sending…'), findsOneWidget);
        expect(
          (await harness.transcriptRows())
              .singleWhere((row) => row.text == _offlinePrompt)
              .status,
          UserMsgStatus.pending,
        );

        requestLiveFault('app_airplane off');
        await _waitAirplaneAck(tester, 'off');
        await eventually<bool>(
          tester,
          () async => await liveRelayHealthReachable() ? true : null,
          description: 'relay reachable after airplane recovery',
        );
        await harness.waitOnlineAndLive(tester: tester);
        final delivered = await eventually<MessageRecord>(
          tester,
          () async {
            final matches = (await harness.transcriptRows()).where(
              (row) => row.text == _offlinePrompt,
            );
            if (matches.isEmpty) return null;
            final row = matches.single;
            return row.status == UserMsgStatus.confirmed ||
                    row.status == UserMsgStatus.failed
                ? row
                : null;
          },
          description: 'held send reaches a visible terminal state',
          timeout: const Duration(seconds: 25),
        );
        expect(delivered.status, UserMsgStatus.confirmed);
        expect(find.text('sending…'), findsNothing);

        final queueEvents = (await harness.captureEvents()).where(
          (event) => event['tag'] == 'sendQueue',
        );
        expect(queueEvents.any((event) => event['phase'] == 'held'), isTrue);
        expect(
          queueEvents.any(
            (event) => event['phase'] == 'resend' && event['outcome'] == 'sent',
          ),
          isTrue,
        );
      } finally {
        requestLiveFault('app_airplane off');
        try {
          await _waitAirplaneAck(tester, 'off');
        } on Object {
          // Preserve the original scenario failure; runner cleanup also resets it.
        }
        await harness.close(tester);
      }
    },
    skip: _phase == 'blank-cold',
    timeout: const Timeout(Duration(minutes: 6)),
  );

  /// Invariant 1: relay-down pairing fails visibly and a retry can pair.
  testWidgets(
    'pairing with relay down fails visibly then succeeds after resume',
    (tester) async {
      final harness = await LiveDeviceHarness.create(restorePair: true);
      try {
        await harness.host.delete('/pair-code');
        await harness.host.post('/command', <String, Object>{'args': 'pair'});
        final firstCode = await eventually<Map<String, dynamic>>(
          tester,
          () async {
            final value = await harness.host.tryGet('/pair-code');
            return value?['uri'] is String ? value : null;
          },
          description: 'pair code before relay pause',
        );

        requestLiveFault('relay_pause');
        await eventually<bool>(
          tester,
          () async => await liveRelayHealthReachable() ? null : true,
          description: 'paused relay boundary',
        );
        final error = await harness.pairFailureFromUri(
          tester,
          firstCode['uri'] as String,
        );
        expect(error, isNotEmpty);
        expect(find.text(error), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);

        requestLiveFault('relay_resume');
        await eventually<bool>(
          tester,
          () async => await liveRelayHealthReachable() ? true : null,
          description: 'resumed relay boundary',
          timeout: const Duration(seconds: 30),
        );
        await harness.host.delete('/pair-code');
        await harness.host.post('/command', <String, Object>{'args': 'pair'});
        final retryCode = await eventually<Map<String, dynamic>>(
          tester,
          () async {
            final value = await harness.host.tryGet('/pair-code');
            return value?['uri'] is String ? value : null;
          },
          description: 'fresh pair code after relay resume',
        );
        await harness.retryPairFromUri(tester, retryCode['uri'] as String);
        expect(harness.connection.status, isA<StatusOnline>());
      } finally {
        await harness.close(tester);
      }
    },
    skip: _phase == 'blank-cold',
    timeout: const Timeout(Duration(minutes: 6)),
  );

  /// Invariants 1/3: a preserving Pi restart keeps history and next delivery.
  testWidgets(
    'extension restart preserves transcript and delivers the next send',
    (tester) async {
      final harness = await LiveDeviceHarness.create(restorePair: true);
      try {
        await harness.mountChat(tester);
        await harness.sendAndResolve(
          tester,
          prompt: _beforeRestartPrompt,
          reply: _beforeRestartReply,
        );
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
          description: 'preserving pi-host restart generation',
          timeout: const Duration(seconds: 45),
        );
        await harness.waitOnlineAndLive(tester: tester);

        await harness.host.post('/turn-control/defer-next', <String, Object>{
          'reply': _afterRestartReply,
        });
        await harness.sync.sendMessage(_afterRestartPrompt);
        await eventually<Map<String, dynamic>>(tester, () async {
          final value = await harness.host.tryGet('/turn-control');
          return value?['phase'] == 'pending' ? value : null;
        }, description: 'post-restart turn reaches the Pi');
        await harness.host.post(
          '/turn-control/resolve',
          const <String, Object>{},
        );
        await eventually<bool>(
          tester,
          () async =>
              find.text(_afterRestartReply).evaluate().isNotEmpty ? true : null,
          description: 'post-restart assistant bubble',
        );
        expect(find.text(_afterRestartPrompt), findsOneWidget);
        expect(find.text(_afterRestartReply), findsOneWidget);
        final text = (await harness.transcriptRows()).map((row) => row.text);
        expect(
          text,
          containsAll(<String>[
            _beforeRestartPrompt,
            _beforeRestartReply,
            _afterRestartPrompt,
            _afterRestartReply,
          ]),
        );
      } finally {
        await harness.close(tester);
      }
    },
    skip: _phase == 'blank-cold',
    timeout: const Timeout(Duration(minutes: 6)),
  );
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

@Tags(['e2e'])
library;

import 'dart:convert';

import 'package:app/data/debug/debug_capture_uploader.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/ui/chat/quick_actions/states/quick_actions_state.dart';
import 'package:app/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart';
import 'package:app/ui/chat/quick_actions/widgets/quick_actions_sheet.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'support/live_device_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Send debug logs delivers a parseable capture into the paired Pi room cwd',
    (tester) async {
      final harness = await LiveDeviceHarness.create(restorePair: false);
      await harness.pair(tester);
      final uploader = DebugCaptureUploaderImpl(
        harness.debugLog,
        harness.connection,
        deviceLabel: () => 'E2E Android device',
      );
      final quickActions = QuickActionsViewModel(harness.actions, uploader);
      try {
        await harness.debugLog.clear();
        harness.debugLog.log(
          ConnStatusEvent(
            ts: DateTime.utc(2026, 8, 25, 12),
            status: 'online',
            peerTail: 'e2e-peer',
            room: harness.peer.roomId,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildDarkTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ChangeNotifierProvider.value(
                  value: quickActions,
                  child: QuickActionsSheetBody(
                    messenger: ScaffoldMessenger.of(context),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('qa-send-debug-logs')));

        await eventually<bool>(
          tester,
          () async => find.text('Debug logs delivered').evaluate().isNotEmpty
              ? true
              : null,
          description: 'delivered capture quick-action state',
        );
        final deliveredPath = quickActions.captureDelivery;
        expect(deliveredPath, isA<CaptureDeliveryDelivered>());

        final capture = await eventually<Map<String, dynamic>>(
          tester,
          () => harness.host.tryGet('/debug-capture/latest'),
          description: 'capture committed under pi-host cwd',
        );
        expect(capture['cwd'], startsWith('/tmp/outpost-pi-e2e-cwd'));
        expect(capture['path'], startsWith('debug/app-capture-'));
        final rows = const LineSplitter().convert(
          utf8.decode(base64Decode(capture['content_base64'] as String)),
        );
        expect(rows, isNotEmpty);
        expect(
          rows.map((line) => jsonDecode(line) as Map<String, dynamic>),
          contains(
            predicate<Map<String, dynamic>>(
              (row) => row['tag'] == 'connStatus',
            ),
          ),
        );

        final events = await eventually<Map<String, dynamic>>(tester, () async {
          final value = await harness.host.tryGet('/events');
          final list = value?['events'];
          if (list is! List) return null;
          final visible = list.whereType<Map>().any((event) {
            final payload = event['payload'];
            return event['kind'] == 'tui_message' &&
                payload is Map &&
                payload['customType'] == 'outpost-pi:debug-capture-delivered' &&
                payload['content'].toString().contains(
                  'Debug capture delivered:',
                );
          });
          return visible ? value : null;
        }, description: 'session-visible delivered note');
        expect(events['events'], isNotEmpty);
      } finally {
        quickActions.dispose();
        await harness.close(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}

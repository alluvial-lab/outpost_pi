@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/live_device_harness.dart';

const _skipSessionRotationLateEchoWorking = false;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Regression for late duplicate echoes after an authoritative idle update.
  // The working=false assertion remains intact in exerciseMultiSessionShape.
  testWidgets(
    'multi-session A to B to A keeps projections and working isolated',
    (tester) async {
      final harness = await _pairedHarness(tester);
      try {
        final sessions = await harness.exerciseMultiSessionShape(tester);
        expect(sessions.sessionA, isNot(sessions.sessionB));
      } finally {
        requestLiveFault('net_clear');
        await harness.close(tester);
      }
    },
    skip: _skipSessionRotationLateEchoWorking,
    timeout: const Timeout(Duration(minutes: 7)),
  );

  testWidgets(
    'mid-conversation unpair and re-pair preserves identity and transcript',
    (tester) async {
      final harness = await _pairedHarness(tester);
      try {
        await harness.exerciseRePairShape(tester);
      } finally {
        requestLiveFault('net_clear');
        await harness.close(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );

  testWidgets(
    'bounded long uptime rotates capture and dedupes reconnect replay',
    (tester) async {
      final harness = await _pairedHarness(tester);
      try {
        await harness.exerciseLongUptimeShape(tester);
      } finally {
        requestLiveFault('net_clear');
        await harness.close(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}

Future<LiveDeviceHarness> _pairedHarness(WidgetTester tester) async {
  final harness = await LiveDeviceHarness.create(restorePair: false);
  await harness.pair(tester);
  await harness.mountChat(tester);
  return harness;
}

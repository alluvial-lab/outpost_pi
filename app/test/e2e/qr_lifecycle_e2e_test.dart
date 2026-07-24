@Tags(['e2e'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'support/harness_endpoints.dart';
import 'support/pairing_stack.dart';
import 'support/pi_host_client.dart';

void main() {
  test(
    'session_start then pair publishes a usable headless pair code',
    () async {
      final endpoints = HarnessEndpoints.fromEnvironment();
      final host = PiHostClient(endpoints.piHost);
      final status = await host.restartForIsolation();

      expect(status.sessionContextHasMessageActions, isFalse);
      expect(status.roomId, isNot('main'));

      final pairCode = await waitForPairCode(host);
      expect(pairCode.qr.roomId, status.roomId);
      expect(pairCode.qr.roomId, isNot('main'));
      expect(pairCode.qr.epkBytes, hasLength(32));
      expect(base64Url.decode(_padded(pairCode.qr.token)), hasLength(16));

      final events = await host.eventsAfter(0);
      expect(
        events.where((event) {
          final payload = event.payload;
          return event.kind == 'tui_message' &&
              payload is Map<String, dynamic> &&
              payload['customType'] == 'outpost-pi:pair-code';
        }),
        isEmpty,
        reason: 'the bearer token must not enter SDK messages/model context',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

String _padded(String value) => value + '=' * ((4 - value.length % 4) % 4);

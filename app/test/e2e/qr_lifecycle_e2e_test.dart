@Tags(['e2e'])
library;

import 'dart:convert';

import 'package:app/pairing/qr_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/eventually.dart';
import 'support/harness_endpoints.dart';
import 'support/pi_host_client.dart';

void main() {
  test('session_start then pair displays a usable QR message', () async {
    final endpoints = HarnessEndpoints.fromEnvironment();
    final host = PiHostClient(endpoints.piHost);
    final status = await host.restartForIsolation();

    expect(status.sessionContextHasMessageActions, isFalse);
    expect(status.roomId, isNot('main'));

    await host.invokeOutpostPi('pair');
    final event = await eventually<PiHostEvent>(
      () async {
        final events = await host.eventsAfter(0);
        for (final candidate in events) {
          final payload = candidate.payload;
          if (candidate.kind == 'tui_message' &&
              payload is Map<String, dynamic> &&
              payload['customType'] == 'outpost-pi:pair-code') {
            return candidate;
          }
        }
        return null;
      },
      timeout: const Duration(seconds: 10),
      description: 'SDK-accepted pair-code TUI message',
    );

    final payload = event.payload! as Map<String, dynamic>;
    expect(payload['display'], isTrue);
    expect(payload['customType'], 'outpost-pi:pair-code');
    final details = payload['details']! as Map<String, dynamic>;
    final qr = QrPairPayload.tryParse(details['uri']! as String);
    expect(qr, isNotNull);
    expect(qr!.roomId, status.roomId);
    expect(qr.roomId, isNot('main'));
    expect(qr.epkBytes, hasLength(32));
    expect(base64Url.decode(_padded(qr.token)), hasLength(16));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

String _padded(String value) =>
    value + '=' * ((4 - value.length % 4) % 4);

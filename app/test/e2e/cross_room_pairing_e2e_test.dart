@Tags(['e2e'])
library;

import 'package:app/pairing/storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/eventually.dart';
import 'support/harness_endpoints.dart';
import 'support/pairing_stack.dart';
import 'support/pi_host_client.dart';
import 'support/secure_storage_fixture.dart';

void main() {
  test('main-room app pairs with a non-main cwd room', () async {
    final endpoints = HarnessEndpoints.fromEnvironment();
    final host = PiHostClient(endpoints.piHost);
    final status = await host.restartForIsolation();
    final pairCode = await waitForPairCode(host);
    final secureStorage = SecureStorageFixture();
    final storage = PairingStorage(secureStorage);
    final stack = await PairingStack.connect(
      endpoints: endpoints,
      qr: pairCode.qr,
      storage: storage,
    );
    addTearDown(stack.close);

    expect(pairCode.qr.roomId, status.roomId);
    expect(pairCode.qr.roomId, isNot('main'));

    final result = await stack.pair(deviceName: 'E2E Phone');
    expect(result.peer.roomId, status.roomId);
    final persisted = await storage.loadPeer(result.peer.remoteEpk);
    expect(persisted, isNotNull);
    expect(persisted!.roomId, status.roomId);

    final pairedStatus = await eventually<PiHostStatus>(
      () async {
        final value = await host.status();
        return value.state == 'paired' ? value : null;
      },
      timeout: const Duration(seconds: 10),
      description: 'Pi host paired state',
    );
    expect(pairedStatus.sessionId, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

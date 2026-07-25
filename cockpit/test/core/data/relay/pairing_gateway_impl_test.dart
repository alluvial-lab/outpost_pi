import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/relay/ephemeral_pi_rpc.dart';
import 'package:cockpit/app/core/data/relay/pairing_gateway_impl.dart';
import 'package:cockpit/app/core/domain/entities/pair_event.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PairingGatewayImpl', () {
    test('polls the pair-code seam and emits PairCodeReady', () async {
      final rpc = _FakeEphemeralPiRpc();
      final gateway = _gateway(rpc);
      final code = _nextEvent<PairCodeReady>(gateway.events);

      await gateway.start();
      final pairCodeFile = File(rpc.pairCodeFile!);
      await pairCodeFile.writeAsString(
        jsonEncode(<String, Object>{
          'uri': 'outpostpi://pair?t=token-123',
          'token': 'token-123',
          'expiresAt': 1760000000000,
          'roomId': 'room-1',
          'name': 'Desk Pi',
        }),
      );

      final event = await code.timeout(const Duration(seconds: 1));
      expect(event.uri, 'outpostpi://pair?t=token-123');
      expect(event.token, 'token-123');
      expect(event.expiresAt, '1760000000000');
      expect(event.roomId, 'room-1');
      expect(event.name, 'Desk Pi');
      await gateway.cancel();
    });

    test(
      'emits PairFailed when the pair-code seam stays empty through boot',
      () async {
        final rpc = _FakeEphemeralPiRpc();
        final gateway = _gateway(
          rpc,
          bootTimeout: const Duration(milliseconds: 1),
        );
        final failure = _nextEvent<PairFailed>(gateway.events);

        await gateway.start();

        expect(
          (await failure.timeout(const Duration(seconds: 1))).message,
          contains('Could not start pairing'),
        );
        await gateway.cancel();
      },
    );

    test('cleanup deletes the cockpit-owned pair-code file', () async {
      final rpc = _FakeEphemeralPiRpc();
      final gateway = _gateway(rpc);
      final code = _nextEvent<PairCodeReady>(gateway.events);

      await gateway.start();
      final pairCodeFile = File(rpc.pairCodeFile!);
      await pairCodeFile.writeAsString(
        jsonEncode(<String, Object>{
          'uri': 'outpostpi://pair?t=token-123',
          'token': 'token-123',
          'expiresAt': 1760000000000,
          'roomId': 'room-1',
          'name': 'Desk Pi',
        }),
      );
      await code.timeout(const Duration(seconds: 1));
      final pairCodeDirectory = pairCodeFile.parent;

      await gateway.cancel();

      expect(pairCodeFile.existsSync(), isFalse);
      expect(pairCodeDirectory.existsSync(), isFalse);
      expect(rpc.disposed, isTrue);
    });
  });
}

PairingGatewayImpl _gateway(
  _FakeEphemeralPiRpc rpc, {
  Duration bootTimeout = const Duration(seconds: 30),
}) => PairingGatewayImpl(
  const PiSpawnConfig(executable: 'pi'),
  rpc: rpc,
  bootTimeout: bootTimeout,
  pollInterval: const Duration(milliseconds: 1),
);

Future<T> _nextEvent<T extends PairEvent>(Stream<PairEvent> events) async =>
    (await events.firstWhere((event) => event is T)) as T;

final class _FakeEphemeralPiRpc implements EphemeralPiRpcSession {
  String? pairCodeFile;
  bool disposed = false;

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<void> start({
    required String prompt,
    required void Function(Map<String, dynamic> json) onLine,
    void Function(int code)? onExit,
    Map<String, String> additionalEnvironment = const <String, String>{},
  }) async {
    pairCodeFile = additionalEnvironment['OUTPOST_PI_PAIR_CODE_FILE'];
  }
}

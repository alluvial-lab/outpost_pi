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
      final timers = _FakeTimers();
      final gateway = _gateway(rpc, timers);
      final code = _nextEvent<PairCodeReady>(gateway.events);

      await gateway.start();
      final pairCodeFile = File(rpc.pairCodeFile!);
      await pairCodeFile.writeAsString(
        jsonEncode(<String, Object>{
          'uri': 'https://outpost-pi.kevoun.com/pair#t=token-123',
          'token': 'token-123',
          'expiresAt': 1760000000000,
          'roomId': 'room-1',
          'name': 'Desk Pi',
        }),
      );
      timers.firePeriodic();

      final event = await code;
      expect(event.uri, 'https://outpost-pi.kevoun.com/pair#t=token-123');
      expect(event.token, 'token-123');
      expect(event.expiresAt, '1760000000000');
      expect(event.roomId, 'room-1');
      expect(event.name, 'Desk Pi');
      expect(timers.periodic!.cancelled, isTrue);
      expect(timers.once!.cancelled, isTrue);
      await gateway.cancel();
    });

    test(
      'boot timeout finalizes the process, bearer-token seam, and timers',
      () async {
        final rpc = _FakeEphemeralPiRpc();
        final timers = _FakeTimers();
        final gateway = _gateway(rpc, timers);
        final failure = _nextEvent<PairFailed>(gateway.events);
        final eventsDone = gateway.events.drain<void>();

        await gateway.start();
        final pairCodeFile = File(rpc.pairCodeFile!);
        final pairCodeDirectory = pairCodeFile.parent;
        timers.fireOnce();

        expect((await failure).message, contains('Could not start pairing'));
        await eventsDone;
        expect(rpc.disposeCalls, 1);
        expect(pairCodeFile.existsSync(), isFalse);
        expect(pairCodeDirectory.existsSync(), isFalse);
        expect(timers.periodic!.cancelled, isTrue);
        expect(timers.once!.cancelled, isTrue);
      },
    );

    test('process exit during startup cannot install orphan timers', () async {
      final rpc = _FakeEphemeralPiRpc(exitDuringStart: true);
      final timers = _FakeTimers();
      final gateway = _gateway(rpc, timers);
      final failure = _nextEvent<PairFailed>(gateway.events);
      final eventsDone = gateway.events.drain<void>();

      final starting = gateway.start();
      await rpc.startEntered.future;
      final pairCodeDirectory = File(rpc.pairCodeFile!).parent;
      await rpc.disposeCompleted.future;
      await eventsDone;
      expect(pairCodeDirectory.existsSync(), isFalse);
      expect(timers.periodic, isNull);
      expect(timers.once, isNull);

      rpc.releaseStart();
      await starting;
      expect((await failure).message, contains('exited (code=17)'));
      expect(timers.periodic, isNull);
      expect(timers.once, isNull);
    });

    test('cancel deletes the cockpit-owned pair-code file', () async {
      final rpc = _FakeEphemeralPiRpc();
      final timers = _FakeTimers();
      final gateway = _gateway(rpc, timers);

      await gateway.start();
      final pairCodeFile = File(rpc.pairCodeFile!);
      final pairCodeDirectory = pairCodeFile.parent;

      await gateway.cancel();

      expect(pairCodeFile.existsSync(), isFalse);
      expect(pairCodeDirectory.existsSync(), isFalse);
      expect(rpc.disposeCalls, 1);
      expect(timers.periodic!.cancelled, isTrue);
      expect(timers.once!.cancelled, isTrue);
    });
  });
}

PairingGatewayImpl _gateway(_FakeEphemeralPiRpc rpc, _FakeTimers timers) =>
    PairingGatewayImpl(
      const PiSpawnConfig(executable: 'pi'),
      rpc: rpc,
      scheduleOnce: timers.scheduleOnce,
      schedulePeriodically: timers.schedulePeriodically,
    );

Future<T> _nextEvent<T extends PairEvent>(Stream<PairEvent> events) async =>
    (await events.firstWhere((event) => event is T)) as T;

final class _FakeEphemeralPiRpc implements EphemeralPiRpcSession {
  _FakeEphemeralPiRpc({this.exitDuringStart = false});

  final bool exitDuringStart;
  final Completer<void> startEntered = Completer<void>();
  final Completer<void> disposeCompleted = Completer<void>();
  final Completer<void> _startRelease = Completer<void>();
  String? pairCodeFile;
  var disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    if (!disposeCompleted.isCompleted) disposeCompleted.complete();
  }

  @override
  Future<void> start({
    required String prompt,
    required void Function(Map<String, dynamic> json) onLine,
    void Function(int code)? onExit,
    Map<String, String> additionalEnvironment = const <String, String>{},
  }) async {
    pairCodeFile = additionalEnvironment['OUTPOST_PI_PAIR_CODE_FILE'];
    if (!exitDuringStart) return;

    startEntered.complete();
    onExit!(17);
    await _startRelease.future;
  }

  void releaseStart() {
    if (!_startRelease.isCompleted) _startRelease.complete();
  }
}

final class _FakeTimers {
  _ScheduledTimer? once;
  _ScheduledTimer? periodic;

  PairingTimerCancel scheduleOnce(Duration duration, void Function() callback) {
    once = _ScheduledTimer(callback);
    return once!.cancel;
  }

  PairingTimerCancel schedulePeriodically(
    Duration duration,
    void Function() callback,
  ) {
    periodic = _ScheduledTimer(callback);
    return periodic!.cancel;
  }

  void fireOnce() => once!.callback();

  void firePeriodic() => periodic!.callback();
}

final class _ScheduledTimer {
  _ScheduledTimer(this.callback);

  final void Function() callback;
  var cancelled = false;

  void cancel() {
    cancelled = true;
  }
}

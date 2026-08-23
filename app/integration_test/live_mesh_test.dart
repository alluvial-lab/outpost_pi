@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:app/data/transport/connection_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/live_device_harness.dart';

const _deliveryMarker = 'mesh lane cross-pi delivery';
const _queuedMarker = 'mesh lane ingress during active run';
const _isolationPrompt = 'mesh lane Pi B isolation prompt';
const _isolationReply = 'mesh lane Pi B isolation reply';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'cross-Pi delivery, active-run ingress queueing, and fault isolation',
    (tester) async {
      final harness = await LiveDeviceHarness.create(
        restorePair: false,
        enableMesh: true,
      );
      try {
        final piA = await harness.pair(tester);
        final piB = await harness.pairSecondary(tester);
        expect(piA.remoteEpk, isNot(piB.remoteEpk));
        expect(piA.roomId, isNot(piB.roomId));
        expect(await harness.storage.listPeers(), hasLength(2));

        await harness.publishMeshMembership();
        final topology = await _waitForMeshTopology(
          tester,
          harness,
          piB.remoteEpk,
        );
        await harness.mountChat(tester);

        await _verifyCrossPiDeviceVisibility(tester, harness, topology);
        debugPrintSynchronously('MESH_SCENARIO_PASS 1 delivery-device-visible');

        await _verifyIngressQueuesUntilSettled(tester, harness, topology);
        debugPrintSynchronously(
          'MESH_SCENARIO_PASS 2 ingress-queued-until-settled',
        );

        await _verifyPiAFaultIsolation(tester, harness, piB.remoteEpk);
        debugPrintSynchronously('MESH_SCENARIO_PASS 3 pi-a-fault-isolated');
      } finally {
        requestLiveFault('net_clear');
        await harness.close(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'post-pair signed membership bootstraps both remote rosters',
    (tester) async {
      final harness = await LiveDeviceHarness.create(
        restorePair: false,
        enableMesh: true,
      );
      try {
        await harness.pair(tester);
        await harness.pairSecondary(tester);
        await harness.publishMeshMembership();
        await _waitForMutualRemoteRoster(tester, harness);
      } finally {
        await harness.close(tester);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

final class _MeshTopology {
  const _MeshTopology({
    required this.piBPubkey,
    required this.piBRoom,
    required this.piBAddress,
  });

  final String piBPubkey;
  final String piBRoom;
  final String piBAddress;
}

Future<_MeshTopology> _waitForMeshTopology(
  WidgetTester tester,
  LiveDeviceHarness harness,
  String piBPubkey,
) async {
  final hostB = LiveHostClient(Uri.parse(livePiHostBUrl));
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  var attempts = 0;
  var lastState = 'not observed';
  while (DateTime.now().isBefore(deadline)) {
    if (attempts++ % 8 == 0) {
      await harness.host.post('/mesh/refresh', const <String, Object>{});
      await hostB.post('/mesh/refresh', const <String, Object>{});
    }
    final a = await harness.host.tryGet('/mesh');
    final b = await hostB.tryGet('/mesh');
    if (a != null && b != null) {
      final bAddress = b['address'];
      final aPeers = (a['peers'] as List?)?.whereType<String>().toList() ?? [];
      final bPeers = (b['peers'] as List?)?.whereType<String>().toList() ?? [];
      String? target;
      if (bAddress is String) {
        try {
          final resolved = await harness.host.post(
            '/mesh/target',
            <String, Object>{'pcPubkey': piBPubkey, 'remoteAddress': bAddress},
          );
          target = resolved['target'] as String?;
        } on Object {
          target = null;
        }
      }
      final ready =
          a['bridgeActive'] == true &&
          b['bridgeActive'] == true &&
          target != null;
      lastState =
          'bridgeA=${a['bridgeActive']} bridgeB=${b['bridgeActive']} '
          'peersA=${aPeers.length} peersB=${bPeers.length} target=$ready';
      if (ready) {
        final room = harness.peer.roomId;
        if (room == null) throw StateError('Pi B room is unavailable');
        return _MeshTopology(
          piBPubkey: piBPubkey,
          piBRoom: room,
          piBAddress: bAddress as String,
        );
      }
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  throw TimeoutException(
    'timed out waiting for mutual broker-issued cross-Pi topology ($lastState)',
    const Duration(seconds: 60),
  );
}

Future<void> _waitForMutualRemoteRoster(
  WidgetTester tester,
  LiveDeviceHarness harness,
) async {
  final hostB = LiveHostClient(Uri.parse(livePiHostBUrl));
  await eventually<bool>(
    tester,
    () async {
      await harness.host.post('/mesh/refresh', const <String, Object>{});
      await hostB.post('/mesh/refresh', const <String, Object>{});
      final a = await harness.host.tryGet('/mesh');
      final b = await hostB.tryGet('/mesh');
      if (a == null || b == null) return null;
      final aAddress = a['address'];
      final bAddress = b['address'];
      final aPeers = (a['peers'] as List?)?.whereType<String>().toList() ?? [];
      final bPeers = (b['peers'] as List?)?.whereType<String>().toList() ?? [];
      return aAddress is String &&
              bAddress is String &&
              aPeers.any((peer) => peer.endsWith(':$bAddress')) &&
              bPeers.any((peer) => peer.endsWith(':$aAddress'))
          ? true
          : null;
    },
    description: 'mutual remote peers_detailed roster',
    timeout: const Duration(seconds: 60),
  );
}

Future<void> _sendMeshAttempt(
  LiveDeviceHarness harness,
  _MeshTopology topology, {
  required String message,
}) async {
  final result = await harness.host.post('/mesh/send-direct', <String, Object>{
    'toPc': topology.piBPubkey,
    'toRoom': topology.piBRoom,
    'toAddress': topology.piBAddress,
    'message': message,
  });
  expect(result['sent'], isTrue);
}

Future<void> _verifyCrossPiDeviceVisibility(
  WidgetTester tester,
  LiveDeviceHarness harness,
  _MeshTopology topology,
) async {
  await _sendMeshAttempt(harness, topology, message: _deliveryMarker);

  await eventually<bool>(
    tester,
    () async => find.text('AGENT-NETWORK').evaluate().isNotEmpty ? true : null,
    description: 'cross-Pi agent-network card on device',
  );
  expect(find.text('AGENT-NETWORK'), findsOneWidget);
}

Future<void> _verifyIngressQueuesUntilSettled(
  WidgetTester tester,
  LiveDeviceHarness harness,
  _MeshTopology topology,
) async {
  final hostB = LiveHostClient(Uri.parse(livePiHostBUrl));
  const prompt = 'mesh lane active-run prompt';
  const reply = 'mesh lane active-run reply';
  await hostB.post('/turn-control/defer-next', <String, Object>{
    'reply': reply,
  });
  await harness.sync.sendMessage(prompt);
  await eventually<Map<String, dynamic>>(tester, () async {
    final value = await hostB.tryGet('/turn-control');
    return value?['phase'] == 'pending' ? value : null;
  }, description: 'Pi B active run barrier');
  await harness.waitForSubmissionVisibility(tester, prompt);

  final eventBaseline = _lastEventSeq(await hostB.get('/events'));
  await _sendMeshAttempt(harness, topology, message: _queuedMarker);
  expect(
    _meshBatchEvents(await hostB.get('/events'), after: eventBaseline),
    isEmpty,
    reason: 'mesh ingress must not enter the SDK while the run is active',
  );

  await hostB.post('/turn-control/resolve', const <String, Object>{});
  await eventually<bool>(
    tester,
    () async => find.text(reply).evaluate().isNotEmpty ? true : null,
    description: 'Pi B run settlement reply',
  );
  final batches = await eventually<List<Map<String, dynamic>>>(
    tester,
    () async {
      final matches = _meshBatchEvents(
        await hostB.get('/events'),
        after: eventBaseline,
      ).where((event) => jsonEncode(event).contains(_queuedMarker)).toList();
      return matches.length == 1 ? matches : null;
    },
    description: 'exactly one post-settlement mesh batch',
  );
  expect(batches, hasLength(1));
  expect(
    harness.connection.isRoomWorking(
      harness.peer.remoteEpk,
      harness.connection.activeRoomId,
    ),
    isFalse,
  );
}

Future<void> _verifyPiAFaultIsolation(
  WidgetTester tester,
  LiveDeviceHarness harness,
  String piBEpk,
) async {
  final hostB = LiveHostClient(Uri.parse(livePiHostBUrl));
  final aBefore = await harness.host.get('/status');
  final bBefore = await hostB.get('/status');
  final selectedBefore = harness.preferences.selectedRoomRaw;

  await hostB.post('/turn-control/defer-next', <String, Object>{
    'reply': _isolationReply,
  });
  requestLiveFault('pi_restart');
  await harness.sync.sendMessage(_isolationPrompt);
  await eventually<Map<String, dynamic>>(tester, () async {
    final value = await hostB.tryGet('/turn-control');
    return value?['phase'] == 'pending' ? value : null;
  }, description: 'Pi B traffic pending while Pi A restarts');
  await harness.waitForSubmissionVisibility(tester, _isolationPrompt);
  await hostB.post('/turn-control/resolve', const <String, Object>{});
  await eventually<bool>(
    tester,
    () async => find.text(_isolationReply).evaluate().isNotEmpty ? true : null,
    description: 'Pi B reply while Pi A restarts',
  );

  final aAfter = await eventually<Map<String, dynamic>>(
    tester,
    () async {
      final value = await harness.host.tryGet('/status');
      return value != null &&
              value['generation'] != aBefore['generation'] &&
              value['relayConnected'] == true
          ? value
          : null;
    },
    description: 'Pi A preserving restart',
    timeout: const Duration(seconds: 45),
  );
  final bAfter = await hostB.get('/status');
  expect(aAfter['generation'], isNot(aBefore['generation']));
  expect(bAfter['generation'], bBefore['generation']);
  expect(harness.peer.remoteEpk, piBEpk);
  expect(harness.preferences.selectedRoomRaw, selectedBefore);
  expect(harness.connection.status, isA<StatusOnline>());
  expect(
    harness.connection.isRoomLive(
      harness.peer.remoteEpk,
      harness.connection.activeRoomId,
    ),
    isTrue,
  );
  expect(find.text(_isolationReply), findsOneWidget);
}

int _lastEventSeq(Map<String, dynamic> response) {
  final events = (response['events'] as List?)?.whereType<Map>().toList() ?? [];
  if (events.isEmpty) return 0;
  return (events.last['seq'] as num).toInt();
}

List<Map<String, dynamic>> _meshBatchEvents(
  Map<String, dynamic> response, {
  required int after,
}) {
  final events = (response['events'] as List?)?.whereType<Map>() ?? const [];
  return [
    for (final raw in events)
      if ((raw['seq'] as num).toInt() > after &&
          raw['payload'] is Map &&
          (raw['payload'] as Map)['customType'] == 'outpost-pi:mesh-message')
        raw.cast<String, dynamic>(),
  ];
}

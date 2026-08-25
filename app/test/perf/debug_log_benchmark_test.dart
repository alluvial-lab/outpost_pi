import 'dart:convert';
import 'dart:io';

import 'package:app/data/debug/debug_log_impl.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _discoveryAdmissionBeforeUs = 4448655;
const _eventCounts = <int>[200, 5500];
const _criticalEventCount = 339;
const _admissionBudgetUs = 75000;
final _enforceLatencyBudgets =
    Platform.environment['OUTPOST_PI_PERF_GATES'] == '1';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('debug_log_benchmark_');
    PathProviderPlatform.instance = _BenchmarkPathProvider(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'debug ring admits the state-shapes flood and coalesces critical flushes',
    () async {
      final log = DebugLogImpl(debugEnabled: () => true);
      final admissionUs = <int, int>{};
      final timestamp = DateTime.utc(2026, 8, 24);

      // Discovery timed this path after the projection/Hive probes had warmed
      // the test isolate. Warm the encoder and admission path before comparing.
      for (var i = 0; i < 50; i++) {
        log.log(
          WsInEvent(
            ts: timestamp,
            bytes: 65536,
            count: i,
            kind: 'envelope',
            stage: 'accepted',
          ),
        );
      }
      await log.clear();

      for (final eventCount in _eventCounts) {
        final stopwatch = Stopwatch()..start();
        for (var i = 0; i < eventCount; i++) {
          log.log(
            WsInEvent(
              ts: timestamp,
              bytes: 65536,
              count: i,
              kind: 'envelope',
              stage: 'accepted',
            ),
          );
        }
        stopwatch.stop();
        admissionUs[eventCount] = stopwatch.elapsedMicroseconds;
        if (eventCount != _eventCounts.last) await log.clear();
      }

      final prefill = await log.export();
      expect(prefill, isNotNull);
      final prefillBytes = utf8.encode('$prefill\n').length;
      expect(prefill!.split('\n'), hasLength(5500));
      expect(prefillBytes, inInclusiveRange(600000, 620000));
      expect(
        admissionUs[5500],
        lessThanOrEqualTo(_discoveryAdmissionBeforeUs ~/ 5),
        reason: 'the locked discovery baseline requires at least a 5x gain',
      );
      if (_enforceLatencyBudgets) {
        expect(
          admissionUs[5500],
          lessThanOrEqualTo(_admissionBudgetUs),
          reason: '5,500-event ring admission exceeded the CI perf budget',
        );
      }

      final writesBeforeBurst = log.snapshotWriteCountForTesting;
      final enqueue = Stopwatch()..start();
      for (var i = 0; i < _criticalEventCount; i++) {
        log.log(
          RoomSnapshotEvent(
            ts: timestamp,
            room: 'benchmark-room-01',
            presenceCount: i,
            working: i.isEven,
          ),
        );
      }
      enqueue.stop();
      final drain = Stopwatch()..start();
      await log.pendingFlush;
      drain.stop();

      final path = '${tempDir.path}/outpost_pi_debug.jsonl';
      final file = File(path);
      final onDisk = await file.readAsLines();
      final last = jsonDecode(onDisk.last) as Map<String, dynamic>;
      final burstWrites = log.snapshotWriteCountForTesting - writesBeforeBurst;
      expect(burstWrites, lessThanOrEqualTo(2));
      expect(last['tag'], 'roomSnapshot');
      expect(last['presenceCount'], _criticalEventCount - 1);

      // ignore: avoid_print - benchmark output is the checked-in evidence format.
      print(
        'PERF_JSON ${jsonEncode(<String, Object>{'probe': 'debug_ring_admission_after', 'events_200_us': admissionUs[200]!, 'events_5500_us': admissionUs[5500]!, 'events_5500_per_event_us': admissionUs[5500]! / 5500, 'prefill_bytes': prefillBytes, 'critical_events': _criticalEventCount, 'critical_enqueue_us': enqueue.elapsedMicroseconds, 'critical_drain_us': drain.elapsedMicroseconds, 'critical_snapshot_writes': burstWrites, 'file_bytes': await file.length()})}',
      );

      log.dispose();
      await log.pendingFlush;
    },
  );
}

final class _BenchmarkPathProvider extends PathProviderPlatform {
  _BenchmarkPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

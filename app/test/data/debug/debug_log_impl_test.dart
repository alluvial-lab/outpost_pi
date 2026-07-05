import 'dart:convert';
import 'dart:io';

import 'package:app/data/debug/debug_log_impl.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Adapter + lifecycle tests (review A2/A3/C3/E3/F2). Uses a real temp dir
/// via the path_provider platform interface override — no I/O mocking of the
/// adapter itself, so the file round-trip is exercised end-to-end.
void main() {
  late _MockPathProvider provider;
  late Directory tempDir;

  setUp(() async {
    provider = _MockPathProvider();
    PathProviderPlatform.instance = provider;
    tempDir = await Directory.systemTemp.createTemp('debug_log_test_');
    provider.appDocsDir = tempDir.path;
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  DebugLogImpl newLog({bool debug = true}) =>
      DebugLogImpl(debugEnabled: () => debug);

  /// Dispose is fire-and-forget (Service.dispose returns void); wait for its
  /// flush to land before reading the file. pumpEventQueue drains the timer +
  /// the async file write.
  Future<void> disposeAndDrain(DebugLogImpl log) async {
    log.dispose();
    await pumpEventQueue(times: 10);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test('log is a no-op when debugEnabled returns false', () async {
    final log = newLog(debug: false);
    log.log(MsgSendEvent(ts: DateTime.now(), id: 'msg-1'));
    expect(await log.export(), isNull);
    log.dispose();
  });

  test('export returns null when empty', () async {
    final log = newLog();
    expect(await log.export(), isNull);
    log.dispose();
  });

  test('log persists to the ring file and survives restart (warm-from-file)',
      () async {
    final path = '${tempDir.path}/remote_pi_debug.jsonl';
    final log1 = newLog();
    log1.log(MsgSendEvent(ts: DateTime.utc(2026, 7, 4), id: 'msg-1'));
    await disposeAndDrain(log1); // final flush
    expect(await File(path).exists(), isTrue);

    // A fresh instance warms from the file.
    final log2 = newLog();
    final exported = await log2.export();
    expect(exported, isNotNull);
    final lines = exported!.split('\n');
    expect(lines, hasLength(1));
    final json = jsonDecode(lines.first) as Map<String, dynamic>;
    expect(json['tag'], 'msgSend');
    expect(json['id'], 'msg-1');
    log2.dispose();
  });

  test('warm-from-file skips corrupt lines without throwing', () async {
    final path = '${tempDir.path}/remote_pi_debug.jsonl';
    // Write a mix of valid + corrupt lines.
    await File(path).writeAsString(
      'not valid json\n'
      '{"tag":"msgEcho","ts":"2026-07-04T00:00:00.000Z","id":"ok-1"}\n'
      '{also not json\n'
      '\n', // empty line
    );
    final log = newLog();
    final exported = await log.export();
    expect(exported, isNotNull);
    final lines = exported!.split('\n');
    expect(lines, hasLength(1));
    expect((jsonDecode(lines.first) as Map<String, dynamic>)['id'], 'ok-1');
    log.dispose();
  });

  test('cap enforced on append — oldest lines dropped, no unbounded growth',
      () async {
    final log = DebugLogImpl.withMaxBytesForTest(
      debugEnabled: () => true,
      maxBytes: 300, // tiny cap so a few lines trigger truncation
    );
    for (var i = 0; i < 50; i++) {
      log.log(MsgSendEvent(ts: DateTime.now(), id: 'msg-$i'));
    }
    final exported = await log.export();
    expect(exported, isNotNull);
    final totalBytes = exported!.length;
    expect(
      totalBytes,
      lessThanOrEqualTo(300 + 50),
      reason: 'ring must stay under cap (+slack for line joins)',
    );
    // Oldest lines evicted; only the most recent survive.
    final lines = exported.split('\n');
    expect(lines.last, contains('msg-49'));
    expect(exported, isNot(contains('msg-0')));
    log.dispose();
  });

  test('a huge untrusted string field cannot evict the window alone', () async {
    final log = DebugLogImpl.withMaxBytesForTest(
      debugEnabled: () => true,
      maxBytes: 2000,
    );
    // A 4000-char error string — capped to 256 per field before encode.
    log.log(WsInEvent(ts: DateTime.now(), error: 'x' * 4000));
    final exported = await log.export();
    final json =
        jsonDecode(exported!.split('\n').first) as Map<String, dynamic>;
    expect((json['error'] as String).length, lessThanOrEqualTo(256));
    log.dispose();
  });

  test('critical events flush immediately (survive a simulated crash)',
      () async {
    final path = '${tempDir.path}/remote_pi_debug.jsonl';
    final log = newLog();
    log.log(ConnChannelLostEvent(ts: DateTime.now(), stale: false));
    await disposeAndDrain(log); // the immediate flush + dispose re-flush
    final onDisk = await File(path).readAsString();
    expect(onDisk, contains('connChannelLost'));
    expect(onDisk, contains('"stale":false'));
  });

  test('clear wipes ring + file but the log can be used again', () async {
    final log = newLog();
    log.log(MsgSendEvent(ts: DateTime.now(), id: 'msg-1'));
    expect(await log.export(), isNotNull);
    await log.clear();
    expect(await log.export(), isNull);
    // Reusable after clear.
    log.log(MsgEchoEvent(ts: DateTime.now(), id: 'echo-1'));
    final exported = await log.export();
    expect(exported, contains('echo-1'));
    log.dispose();
  });

  test('dispose flushes pending lines (lifecycle — review C3)', () async {
    final path = '${tempDir.path}/remote_pi_debug.jsonl';
    final log = newLog();
    // A routine (non-critical) event: stays pending until the debounce fires.
    log.log(ReplayDedupEvent(ts: DateTime.now(), sessionId: 's1', dropped: true));
    // Dispose immediately — must flush the pending line.
    await disposeAndDrain(log);
    final onDisk = await File(path).readAsString();
    expect(onDisk, contains('replayDedup'));
  });

  test('never throws — file I/O failure does not propagate', () async {
    // Point path_provider at a non-existent dir to force I/O failure.
    provider.appDocsDir = '/nonexistent/path/that/does/not/exist';
    final log = newLog();
    // None of these should throw.
    log.log(MsgSendEvent(ts: DateTime.now(), id: 'msg-1'));
    await disposeAndDrain(log);
    await log.export();
    await log.clear();
    // Reached here → no throw.
    expect(true, isTrue);
  });

  test('export reads from the file (source of truth) after a forced flush',
      () async {
    final path = '${tempDir.path}/remote_pi_debug.jsonl';
    // Pre-write a line directly to the file (simulating a prior session).
    await File(path).writeAsString(
      '{"tag":"msgEcho","ts":"2026-07-04T00:00:00.000Z","id":"pre-existing"}\n',
    );
    final log = newLog();
    // Don't log anything new — export should read the pre-existing file.
    final exported = await log.export();
    expect(exported, contains('pre-existing'));
    log.dispose();
  });
}

/// Mock path_provider so tests use a real temp dir (no Android/iOS plugin).
class _MockPathProvider extends PathProviderPlatform {
  String? appDocsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => appDocsDir;

  @override
  Future<String?> getApplicationSupportPath() async => appDocsDir;

  @override
  Future<String?> getTemporaryPath() async => appDocsDir;
}

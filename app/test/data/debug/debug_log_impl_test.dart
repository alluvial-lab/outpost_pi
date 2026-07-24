import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:app/config/dependencies.dart';
import 'package:app/data/debug/debug_log_impl.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  test(
    'Preferences.debugLogging gates capture through the injected callback',
    () async {
      final prefs = Preferences(_FakeSecureStorage());
      final log = DebugLogImpl(debugEnabled: () => prefs.debugLogging);

      log.log(MsgSendEvent(ts: DateTime.now(), id: 'off-1'));
      expect(await log.export(), isNull);

      await prefs.setDebugLogging(true);
      log.log(MsgSendEvent(ts: DateTime.now(), id: 'on-1'));
      var exported = await log.export();
      expect(exported, contains('on-1'));
      expect(exported, isNot(contains('off-1')));

      await prefs.setDebugLogging(false);
      log.log(MsgSendEvent(ts: DateTime.now(), id: 'off-2'));
      exported = await log.export();
      expect(exported, contains('on-1'));
      expect(exported, isNot(contains('off-2')));
      log.dispose();
    },
  );

  test('export returns null when empty', () async {
    final log = newLog();
    expect(await log.export(), isNull);
    log.dispose();
  });

  test(
    'log persists to the ring file and survives restart (warm-from-file)',
    () async {
      final path = '${tempDir.path}/outpost_pi_debug.jsonl';
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
    },
  );

  test('warm-from-file skips corrupt lines without throwing', () async {
    final path = '${tempDir.path}/outpost_pi_debug.jsonl';
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

  test(
    'legacy lines carrying forbidden keys are dropped at load and export',
    () async {
      const secret = '/Users/operator/workspace token=secret-7F3A';
      final path = '${tempDir.path}/outpost_pi_debug.jsonl';
      // Pre-upgrade rows: MsgFailedEvent.detail and SessionSyncEvent.err once
      // carried arbitrary capped text. They must never egress again.
      await File(path).writeAsString(
        '{"tag":"msgFailed","ts":"2026-07-20T00:00:00.000Z",'
        '"id":"m-1","code":"internal_error","detail":"$secret"}\n'
        '{"tag":"sessionSync","ts":"2026-07-20T00:00:01.000Z",'
        '"err":"$secret"}\n'
        '{"tag":"msgEcho","ts":"2026-07-20T00:00:02.000Z","id":"ok-1"}\n',
      );
      final log = newLog();
      final exported = await log.export();
      expect(exported, isNotNull);
      expect(exported, contains('ok-1'));
      expect(exported, isNot(contains(secret)));
      expect(exported, isNot(contains('"detail"')));
      expect(exported, isNot(contains('"err"')));
      log.dispose();
    },
  );

  test(
    'cap enforced on append — oldest lines dropped, no unbounded growth',
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
    },
  );

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

  test(
    'critical events flush immediately (survive a simulated crash)',
    () async {
      final path = '${tempDir.path}/outpost_pi_debug.jsonl';
      final log = newLog();
      log.log(ConnChannelLostEvent(ts: DateTime.now(), stale: false));
      await disposeAndDrain(log); // the immediate flush + dispose re-flush
      final onDisk = await File(path).readAsString();
      expect(onDisk, contains('connChannelLost'));
      expect(onDisk, contains('"stale":false'));
    },
  );

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
    final path = '${tempDir.path}/outpost_pi_debug.jsonl';
    final log = newLog();
    // A routine (non-critical) event: stays pending until the debounce fires.
    log.log(
      ReplayDedupEvent(ts: DateTime.now(), sessionId: 's1', dropped: true),
    );
    // Dispose immediately — must flush the pending line.
    await disposeAndDrain(log);
    final onDisk = await File(path).readAsString();
    expect(onDisk, contains('replayDedup'));
  });

  test(
    'disposeDependencies flushes DebugLogImpl registered via addService',
    () async {
      final path = '${tempDir.path}/outpost_pi_debug.jsonl';
      final prefs = Preferences(_FakeSecureStorage());
      await prefs.setDebugLogging(true);
      injector.addService<DebugLog>(
        () => DebugLogImpl(debugEnabled: () => prefs.debugLogging),
      );
      injector.commit();

      final log = injector.get<DebugLog>();
      log.log(
        ReplayDedupEvent(ts: DateTime.now(), sessionId: 's1', dropped: true),
      );
      disposeDependencies();
      await pumpEventQueue(times: 10);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final onDisk = await File(path).readAsString();
      expect(onDisk, contains('replayDedup'));
    },
  );

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

  test(
    'export reads from the file (source of truth) after a forced flush',
    () async {
      final path = '${tempDir.path}/outpost_pi_debug.jsonl';
      // Pre-write a line directly to the file (simulating a prior session).
      await File(path).writeAsString(
        '{"tag":"msgEcho","ts":"2026-07-04T00:00:00.000Z","id":"pre-existing"}\n',
      );
      final log = newLog();
      // Don't log anything new — export should read the pre-existing file.
      final exported = await log.export();
      expect(exported, contains('pre-existing'));
      log.dispose();
    },
  );

  test(
    'snapshot-write: on-disk file is capped (no unbounded growth)',
    () async {
      // The blocker fix: the file is an atomic snapshot of the capped ring, not
      // append-only. So evicted lines don't persist on disk.
      final log = DebugLogImpl.withMaxBytesForTest(
        debugEnabled: () => true,
        maxBytes: 500, // tiny cap
      );
      for (var i = 0; i < 100; i++) {
        log.log(MsgSendEvent(ts: DateTime.now(), id: 'msg-$i'));
      }
      await log.export(); // force-flush the snapshot
      final path = '${tempDir.path}/outpost_pi_debug.jsonl';
      final onDisk = await File(path).readAsString();
      // The file must be under the cap (+slack for newlines), not 100 lines.
      expect(
        onDisk.length,
        lessThanOrEqualTo(500 + 200),
        reason: 'on-disk file must be capped (snapshot-write, not append-only)',
      );
      expect(onDisk, isNot(contains('msg-0'))); // oldest evicted
      expect(onDisk, contains('msg-99')); // newest retained
      log.dispose();
    },
  );

  test(
    'export recovers on-disk state when the in-memory ring diverged',
    () async {
      final path = '${tempDir.path}/outpost_pi_debug.jsonl';
      // Log a line, flush it to disk, then SIMULATE ring divergence by writing
      // an extra line directly to the file that the ring doesn't know about.
      final log = newLog();
      log.log(MsgEchoEvent(ts: DateTime.now(), id: 'ring-known'));
      await log.export(); // flush ring-known to disk
      log.dispose();
      // Append a line the ring never saw (simulating a prior-session line that
      // warm-from-file would have loaded, but we're testing export-from-file).
      await File(path).writeAsString(
        '{"tag":"msgSend","ts":"2026-07-04T00:00:00.000Z","id":"disk-only"}\n',
        mode: FileMode.append,
      );
      // A fresh instance warms from file (gets both lines), but export reads the
      // FILE — so even if the ring somehow diverged, export reflects disk truth.
      final log2 = newLog();
      final exported = await log2.export();
      expect(exported, contains('ring-known'));
      expect(exported, contains('disk-only'));
      log2.dispose();
    },
  );

  test('log() catches a throwing _debugEnabled callback (never throws)', () {
    final log = DebugLogImpl(debugEnabled: () => throw StateError('boom'));
    // Must not throw — the whole public body is wrapped, including the callback.
    log.log(MsgSendEvent(ts: DateTime.now(), id: 'msg-1'));
    expect(true, isTrue); // reached here → no throw
    log.dispose();
  });

  test('clear serializes with an in-flight flush (no log resurrection)', () async {
    // The v2-blocker regression: a stale snapshot write completing AFTER
    // clear() must not resurrect the wiped logs. clear() awaits the in-flight
    // _flushFuture before wiping.
    //
    // Deterministic proof: log a critical event (starts an immediate flush),
    // capture the in-flight flush future via the test seam, then call clear()
    // and assert clear() does not complete until that flush has settled. If
    // clear() did NOT await the flush, clear() would complete while the flush
    // is still pending — and the stale snapshot could land after the wipe.
    final path = '${tempDir.path}/outpost_pi_debug.jsonl';
    final log = newLog();
    // Hold the flush in-flight long enough to prove clear() awaits it.
    log.flushDelayForTesting = const Duration(seconds: 5);
    log.log(ConnChannelLostEvent(ts: DateTime.now(), stale: false));
    // Yield enough microtasks for _flushNow to: await _ensureLoaded (async,
    // resolves the path), then assign _flushFuture, then reach the delayed write.
    await pumpEventQueue(times: 20);
    final inFlight = log.pendingFlush;
    expect(inFlight, isNotNull, reason: 'a critical event must start a flush');
    // Start clear() WITHOUT awaiting — it should be blocked on the in-flight
    // flush (if the fix is present).
    final clearDone = Completer<void>();
    // ignore: discarded_futures
    log.clear().then((_) => clearDone.complete());
    // Yield once so clear() can run up to its `await prev`.
    await Future<void>.delayed(Duration.zero);
    // The in-flight flush is still pending (held by flushDelayForTesting) —
    // clear() must not have completed yet. If clear() did NOT await the flush,
    // clearDone would be completed here.
    expect(
      clearDone.isCompleted,
      isFalse,
      reason: 'clear() must not complete before the in-flight flush settles',
    );
    // Now let the flush complete.
    log.flushDelayForTesting = null;
    await inFlight;
    await clearDone.future;
    // After both settle, the file must be empty (no resurrection).
    final file = File(path);
    if (await file.exists()) {
      expect(await file.readAsString(), isEmpty);
    }
    expect(await log.export(), isNull);
    log.dispose();
  });

  test('concurrent flushes write in call order (serialized)', () async {
    final path = '${tempDir.path}/outpost_pi_debug.jsonl';
    final log = newLog();
    // Fire many critical logs back-to-back — each triggers an immediate flush.
    for (var i = 0; i < 10; i++) {
      log.log(
        ConnStatusEvent(ts: DateTime.now(), status: 'retrying', attempt: i),
      );
    }
    await log.export(); // drain the flush chain
    final onDisk = await File(path).readAsString();
    // The snapshot contains all 10 (under cap); order is call order (the
    // snapshot is _ring.join, which is append order).
    final lines = onDisk.trim().split('\n');
    final attempts = lines
        .map((l) => (jsonDecode(l) as Map<String, dynamic>)['attempt'] as int?)
        .where((a) => a != null)
        .toList();
    expect(attempts, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    log.dispose();
  });
}

/// Mock path_provider so tests use a real temp dir (no Android/iOS plugin).
class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store.remove(key);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _MockPathProvider extends PathProviderPlatform {
  String? appDocsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => appDocsDir;

  @override
  Future<String?> getApplicationSupportPath() async => appDocsDir;

  @override
  Future<String?> getTemporaryPath() async => appDocsDir;
}

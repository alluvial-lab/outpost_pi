import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/config/dependencies.dart';
import 'package:app/data/debug/debug_log_impl.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:flutter/foundation.dart';
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
      final content = exported!;
      final totalBytes = utf8.encode('$content\n').length;
      expect(
        totalBytes,
        lessThanOrEqualTo(300),
        reason: 'jsonl UTF-8 bytes, including newlines, must stay under cap',
      );
      // Oldest lines evicted; only the most recent survive.
      final lines = content.split('\n');
      expect(lines.last, contains('msg-49'));
      expect(content, isNot(contains('msg-0')));
      log.dispose();
    },
  );

  test(
    '5500-row state-shapes flood retains newest row and rotates oldest',
    () async {
      const ringEvents = 5500;
      const stage =
          'bounded-long-uptime-capture-rotation-probe-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
      final timestamp = DateTime.utc(2026, 8, 24);
      final log = newLog();

      log.log(
        WsInEvent(ts: timestamp, count: -1, kind: 'state-shape', stage: stage),
      );
      for (var index = 0; index < ringEvents; index++) {
        log.log(
          WsInEvent(
            ts: timestamp,
            count: index,
            kind: 'state-shape',
            stage: stage,
          ),
        );
      }

      final firstExport = await log.export();
      expect(firstExport, isNotNull);

      // Match the harness's immediate second capture while a live critical
      // event starts another snapshot write after the force-flush completes.
      final readStarted = Completer<void>();
      final releaseRead = Completer<void>();
      log.beforeExportReadForTesting = () {
        readStarted.complete();
        return releaseRead.future;
      };
      final snapshotReady = Completer<void>();
      final releaseCommit = Completer<void>();
      var snapshotCalls = 0;
      log.beforeSnapshotCommitForTesting = () {
        snapshotCalls += 1;
        if (snapshotCalls == 2) {
          snapshotReady.complete();
          return releaseCommit.future;
        }
        return Future<void>.value();
      };

      final capture = log.export();
      await readStarted.future;
      log.log(
        RoomSnapshotEvent(
          ts: timestamp,
          room: 'state-shapes-room',
          presenceCount: 1,
          working: false,
        ),
      );
      await snapshotReady.future;
      releaseRead.complete();

      final exported = await capture;
      final criticalFlush = log.pendingFlush;
      releaseCommit.complete();
      await criticalFlush;
      expect(exported, isNotNull);
      final rows = const LineSplitter()
          .convert(exported!)
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList(growable: false);
      expect(
        rows.any((row) => row['tag'] == 'wsIn' && row['count'] == -1),
        isFalse,
        reason: 'the oldest flood marker must rotate out',
      );
      expect(
        rows.any(
          (row) => row['tag'] == 'wsIn' && row['count'] == ringEvents - 1,
        ),
        isTrue,
        reason: 'the newest admitted flood row must remain exportable',
      );
      log.dispose();
      await log.pendingFlush;
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

  test(
    'FileSystemException fallbacks are scrubbed and leave no exportable state',
    () async {
      const inaccessibleDir = '/nonexistent/path/that/does/not/exist';
      final diagnostics = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) diagnostics.add(message);
      };
      try {
        // Point path_provider at a non-existent dir to force FileSystemException
        // on log/dispose/export flush attempts; clear must remain contained too.
        provider.appDocsDir = inaccessibleDir;
        final log = newLog();
        log.log(MsgSendEvent(ts: DateTime.now(), id: 'msg-1'));
        await disposeAndDrain(log);
        expect(await log.export(), isNull);
        await log.clear();
        expect(await log.export(), isNull);
      } finally {
        debugPrint = originalDebugPrint;
      }

      expect(diagnostics, isNotEmpty);
      expect(diagnostics, everyElement('[debug-log] flush failed'));
      expect(diagnostics.join('\n'), isNot(contains(inaccessibleDir)));
      expect(diagnostics.join('\n'), isNot(contains('PathNotFoundException')));
      expect(diagnostics.join('\n'), isNot(contains('#0')));
    },
  );

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

  test('a throwing debugEnabled callback leaves no exportable event', () async {
    final log = DebugLogImpl(debugEnabled: () => throw StateError('boom'));
    // The callback failure is contained and no event enters the ring.
    log.log(MsgSendEvent(ts: DateTime.now(), id: 'msg-1'));
    expect(await log.export(), isNull);
    log.dispose();
  });

  test(
    'clear serializes with an in-flight flush (no log resurrection)',
    () async {
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
      final writeStarted = Completer<void>();
      final releaseWrite = Completer<void>();
      log.beforeSnapshotWriteForTesting = () {
        writeStarted.complete();
        return releaseWrite.future;
      };
      log.log(ConnChannelLostEvent(ts: DateTime.now(), stale: false));
      await writeStarted.future;
      final inFlight = log.pendingFlush;
      expect(
        inFlight,
        isNotNull,
        reason: 'a critical event must start a flush',
      );
      // Start clear() WITHOUT awaiting — it should be blocked on the in-flight
      // flush (if the fix is present).
      final clearDone = Completer<void>();
      // ignore: discarded_futures
      log.clear().then((_) => clearDone.complete());
      // Yield once so clear() can run up to its `await activeFlush`.
      await Future<void>.delayed(Duration.zero);
      expect(
        clearDone.isCompleted,
        isFalse,
        reason: 'clear() must not complete before the in-flight flush settles',
      );
      releaseWrite.complete();
      await inFlight;
      await clearDone.future;
      // After both settle, the file must be empty (no resurrection).
      final file = File(path);
      if (await file.exists()) {
        expect(await file.readAsString(), isEmpty);
      }
      expect(await log.export(), isNull);
      log.dispose();
    },
  );

  test(
    'critical burst during an in-flight write coalesces to one trailing snapshot',
    () async {
      final path = '${tempDir.path}/outpost_pi_debug.jsonl';
      final log = newLog();
      final firstWriteStarted = Completer<void>();
      final releaseFirstWrite = Completer<void>();
      var barrierCalls = 0;
      log.beforeSnapshotWriteForTesting = () {
        barrierCalls += 1;
        if (barrierCalls == 1) {
          firstWriteStarted.complete();
          return releaseFirstWrite.future;
        }
        return Future<void>.value();
      };

      log.log(
        ConnStatusEvent(ts: DateTime.now(), status: 'retrying', attempt: 0),
      );
      await firstWriteStarted.future;
      final drain = log.pendingFlush;
      expect(drain, isNotNull);

      // All 338 requests overlap the first captured snapshot. They must set one
      // dirty latch, not append 338 full-file writes to a future chain.
      for (var i = 1; i < 339; i++) {
        log.log(
          ConnStatusEvent(ts: DateTime.now(), status: 'retrying', attempt: i),
        );
      }
      releaseFirstWrite.complete();
      await drain;

      expect(log.snapshotWriteCountForTesting, 2);
      final lines = (await File(path).readAsLines())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList(growable: false);
      expect(lines, hasLength(339));
      expect(lines.last['attempt'], 338);
      log.dispose();
      await log.pendingFlush;
    },
  );
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

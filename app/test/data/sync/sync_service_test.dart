// Plan/31 — SyncService is the single DB writer. Drives it through a fake
// channel adopted into a real ConnectionManager and asserts box contents.

import 'dart:async';
import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/runtime_record.dart';
import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/data/sync/sync_events.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _FakeChannel implements IChannel, IControlLink {
  final _ctrl = StreamController<ServerMessage>.broadcast();
  final _controlCtrl = StreamController<ControlInbound>.broadcast();
  final List<ClientMessage> sent = [];
  final List<Map<String, dynamic>> sentControl = [];
  Object? sendFailure;
  Completer<ClientMessage>? nextSendStarted;
  String defaultSessionId = '';

  @override
  Stream<ServerMessage> get serverMessages => _ctrl.stream;
  @override
  Future<void> send(ClientMessage msg) async {
    final failure = sendFailure;
    if (failure != null) throw failure;
    final started = nextSendStarted;
    nextSendStarted = null;
    if (started != null && !started.isCompleted) started.complete(msg);
    sent.add(msg);
  }

  @override
  Future<void> close() async {
    if (!_ctrl.isClosed) await _ctrl.close();
    if (!_controlCtrl.isClosed) await _controlCtrl.close();
  }

  @override
  Stream<ControlInbound> get controlFrames => _controlCtrl.stream;

  @override
  void sendControl(Map<String, dynamic> json) {
    sentControl.add(json);
  }

  void pushControl(ControlInbound c) {
    if (!_controlCtrl.isClosed) _controlCtrl.add(c);
  }

  void push(ServerMessage m) => _ctrl.add(_withDefaultSession(m));

  void pushRaw(ServerMessage m) => _ctrl.add(m);

  Future<void> loseConnection() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }

  ServerMessage _withDefaultSession(ServerMessage m) {
    final sid = defaultSessionId;
    if (sid.isEmpty) return m;
    return switch (m) {
      UserInput(:final sessionId) when sessionId.isEmpty => UserInput(
        id: m.id,
        sessionId: sid,
        text: m.text,
        streamingBehavior: m.streamingBehavior,
        image: m.image,
        ts: m.ts,
      ),
      QueuedMessageState(:final sessionId) when sessionId.isEmpty =>
        QueuedMessageState(sessionId: sid, id: m.id, text: m.text),
      AgentChunk(:final sessionId) when sessionId.isEmpty => AgentChunk(
        sessionId: sid,
        inReplyTo: m.inReplyTo,
        delta: m.delta,
        ts: m.ts,
      ),
      AgentDone(:final sessionId) when sessionId.isEmpty => AgentDone(
        sessionId: sid,
        inReplyTo: m.inReplyTo,
        usage: m.usage,
        ts: m.ts,
      ),
      AgentMessage(:final sessionId) when sessionId.isEmpty => AgentMessage(
        sessionId: sid,
        inReplyTo: m.inReplyTo,
        text: m.text,
        usage: m.usage,
        ts: m.ts,
        messageId: m.messageId,
      ),
      ToolRequest(:final sessionId) when sessionId.isEmpty => ToolRequest(
        sessionId: sid,
        toolCallId: m.toolCallId,
        tool: m.tool,
        args: m.args,
      ),
      ToolResult(:final sessionId) when sessionId.isEmpty => ToolResult(
        sessionId: sid,
        toolCallId: m.toolCallId,
        result: m.result,
        error: m.error,
      ),
      ErrorMessage(:final sessionId) when sessionId.isEmpty => ErrorMessage(
        sessionId: sid,
        inReplyTo: m.inReplyTo,
        code: m.code,
        message: m.message,
        ts: m.ts,
      ),
      Cancelled(:final sessionId) when sessionId.isEmpty => Cancelled(
        sessionId: sid,
        inReplyTo: m.inReplyTo,
        targetId: m.targetId,
      ),
      Compaction(:final sessionId) when sessionId.isEmpty => Compaction(
        sessionId: sid,
        summary: m.summary,
        tokensBefore: m.tokensBefore,
        ts: m.ts,
      ),
      SessionHistory(:final sessionId) when sessionId.isEmpty => SessionHistory(
        sessionId: sid,
        inReplyTo: m.inReplyTo,
        sessionStartedAt: m.sessionStartedAt,
        events: m.events,
        eos: m.eos,
        truncated: m.truncated,
      ),
      _ => m,
    };
  }
}

class _MemoryTranscriptStore implements TranscriptEventStore {
  final Map<String, List<TranscriptEvent>> _events = {};
  bool failNextAppend = false;
  bool failNextRead = false;
  int appendCalls = 0;
  int readCalls = 0;
  int? failAppendCall;
  Completer<void>? appendGate;
  Completer<void>? appendStarted;
  Completer<void>? readGate;
  Completer<void>? readStarted;

  List<TranscriptEvent> eventsFor(TranscriptSessionKey key) =>
      List<TranscriptEvent>.of(_events[key.durableKey] ?? const []);

  @override
  Future<AppendTranscriptEventsResult> appendAll(
    TranscriptSessionKey key,
    Iterable<TranscriptEvent> events,
  ) async {
    appendCalls += 1;
    final started = appendStarted;
    if (started != null && !started.isCompleted) started.complete();
    final gate = appendGate;
    if (gate != null) {
      appendGate = null;
      await gate.future;
    }
    if (failAppendCall == appendCalls) {
      throw StateError('append failed on call $appendCalls');
    }
    if (failNextAppend) {
      failNextAppend = false;
      throw StateError('append failed');
    }
    final batch = events.toList(growable: false);
    final log = _events.putIfAbsent(key.durableKey, () => []);
    final ids = log.map((event) => event.eventId).toSet();
    final accepted = <SequencedTranscriptEvent>[];
    for (final event in batch) {
      if (ids.add(event.eventId)) {
        final sequence = log.length;
        log.add(event);
        accepted.add(
          SequencedTranscriptEvent(event: event, sequence: sequence),
        );
      }
    }
    return AppendTranscriptEventsResult(
      received: batch.length,
      appended: accepted.length,
      skipped: batch.length - accepted.length,
      accepted: List<SequencedTranscriptEvent>.unmodifiable(accepted),
    );
  }

  @override
  Future<void> clearSession(TranscriptSessionKey key) async {
    _events.remove(key.durableKey);
  }

  @override
  Future<List<TranscriptEvent>> readSession(TranscriptSessionKey key) async {
    readCalls += 1;
    final gate = readGate;
    if (gate != null) {
      readGate = null;
      final started = readStarted;
      if (started != null && !started.isCompleted) started.complete();
      await gate.future;
    }
    if (failNextRead) {
      failNextRead = false;
      throw StateError('read failed');
    }
    return List<TranscriptEvent>.of(_events[key.durableKey] ?? const []);
  }

  @override
  Stream<List<TranscriptEvent>> watchSession(TranscriptSessionKey key) =>
      const Stream<List<TranscriptEvent>>.empty();
}

class _RecordingDebugLog implements DebugLog {
  final List<DebugEvent> events = [];

  @override
  void log(DebugEvent event) => events.add(event);

  @override
  Future<String?> export() async => null;

  @override
  Future<void> clear() async => events.clear();

  @override
  void dispose() {}
}

class _FakeStorage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => const [];
}

class _PendingTimerScheduler {
  Duration _elapsed = Duration.zero;
  final List<_ScheduledPendingTimer> _timers = [];

  PendingSendTimer schedule(Duration delay, void Function() callback) {
    final timer = _ScheduledPendingTimer(_elapsed + delay, callback);
    _timers.add(timer);
    return timer;
  }

  void elapse(Duration duration) {
    _elapsed += duration;
    for (final timer in List<_ScheduledPendingTimer>.of(_timers)) {
      if (!timer.cancelled && timer.deadline <= _elapsed) {
        timer.fire();
      }
    }
    _timers.removeWhere((timer) => timer.cancelled || timer.fired);
  }
}

class _ScheduledPendingTimer implements PendingSendTimer {
  _ScheduledPendingTimer(this.deadline, this._callback);

  final Duration deadline;
  final void Function() _callback;
  bool cancelled = false;
  bool fired = false;

  @override
  void cancel() => cancelled = true;

  void fire() {
    if (cancelled || fired) return;
    fired = true;
    _callback();
  }
}

int _counter = 0;
final Map<String, String> _sessionByEpk = <String, String>{};

late Directory _dir;

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

Future<void> _waitUntil(
  bool Function() condition, {
  required String reason,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

void main() {
  setUpAll(() async {
    _dir = Directory.systemTemp.createTempSync('rp_v2_sync_');
    await LocalBoxes.initForTest(_dir.path);
  });
  tearDownAll(() async {
    await Hive.close();
    await _dir.delete(recursive: true);
  });

  Future<
    ({
      ConnectionManager conn,
      _FakeChannel ch,
      SyncService sync,
      String epk,
      String sessionId,
    })
  >
  setup({
    Duration pendingSendTimeout = const Duration(seconds: 20),
    Duration deliveryPendingEchoTimeout = const Duration(seconds: 60),
    PendingSendTimerFactory? pendingSendTimerFactory,
    TranscriptEventStore? transcriptEventStore,
    DebugLog? debugLog,
    Future<void> Function(String key, Map<String, dynamic> value)?
    runtimeRecordWriter,
  }) async {
    final ch = _FakeChannel();
    final conn = ConnectionManager(
      factory: (_, _) async => ch,
      storage: _FakeStorage(),
    );
    final boxes = LocalBoxes();
    final sync = SyncService(
      conn,
      boxes,
      transcriptEventStore: transcriptEventStore,
      debugLog: debugLog,
      runtimeRecordWriter: runtimeRecordWriter,
      pendingSendTimeout: pendingSendTimeout,
      deliveryPendingEchoTimeout: deliveryPendingEchoTimeout,
      pendingSendTimerFactory: pendingSendTimerFactory,
    );
    final epk = 'epk_sync_${++_counter}';
    final sessionId = 'session_$_counter';
    _sessionByEpk[epk] = sessionId;
    ch.defaultSessionId = sessionId;
    conn.adopt(
      ch,
      PeerRecord(
        remoteEpk: epk,
        sessionName: 'Pi',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-01-01T00:00:00Z',
      ),
    );
    await _settle(); // _onlineActivated → activate(epk) settles
    ch.pushRaw(
      PairOk(
        inReplyTo: 'pair_$_counter',
        sessionName: 'Pi',
        sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
        roomId: 'main',
        sessionId: sessionId,
      ),
    );
    await _settle(); // ConnectionManager learns active session id
    await sync.activate(epk, 'main');
    await _settle();
    return (conn: conn, ch: ch, sync: sync, epk: epk, sessionId: sessionId);
  }

  RemoteSessionRef refFor(String epk, [String? sessionId]) => RemoteSessionRef(
    peerEpk: epk,
    roomId: 'main',
    sessionId: sessionId ?? _sessionByEpk[epk]!,
  );

  TranscriptSessionKey transcriptKeyFor(String epk, [String? sessionId]) =>
      TranscriptSessionKey(
        peerId: epk,
        roomId: 'main',
        sessionId: sessionId ?? _sessionByEpk[epk]!,
      );

  List<MessageRecord> messages(String epk, [String? sessionId]) {
    final ref = refFor(epk, sessionId);
    if (!LocalBoxes().isMsgsBoxOpen(ref)) return const <MessageRecord>[];
    final box = LocalBoxes().openMsgsBox(ref);
    final out = [
      for (final v in box.values)
        MessageRecord.fromJson((v as Map).cast<String, dynamic>()),
    ];
    out.sort((a, b) => a.seq.compareTo(b.seq));
    return out;
  }

  SessionIndexRecord? index(String epk, [String? sessionId]) {
    final raw = LocalBoxes().sessionsIndexBox().get(
      LocalBoxes.sessionKey(refFor(epk, sessionId)),
    );
    return raw is Map
        ? SessionIndexRecord.fromJson(raw.cast<String, dynamic>())
        : null;
  }

  test(
    'two session ids on the same room use different boxes and index keys',
    () async {
      final s = await setup();
      final oldSession = s.sessionId;
      final oldRef = refFor(s.epk, oldSession);
      final oldBoxName = LocalBoxes.msgsBoxName(oldRef);
      final legacyBox = await Hive.openBox<dynamic>(
        'msgs_${toAppEpk(s.epk)}__main',
      );
      await legacyBox.put(0, {'legacy': true});

      s.ch.push(UserInput(id: 'old-u1', text: 'old session row'));
      await _waitUntil(
        () =>
            messages(s.epk, oldSession).singleOrNull?.text ==
                'old session row' &&
            index(s.epk, oldSession)?.key == '${s.epk}:main:$oldSession',
        reason: 'the old session row and index update to settle',
      );
      expect(messages(s.epk, oldSession).map((row) => row.text), [
        'old session row',
      ]);
      expect(index(s.epk, oldSession)?.key, '${s.epk}:main:$oldSession');

      const rotatedSession = 'session-rotated-same-room';
      _sessionByEpk[s.epk] = rotatedSession;
      s.ch.defaultSessionId = rotatedSession;
      s.ch.pushRaw(
        PairOk(
          inReplyTo: 'pair-rotated',
          sessionName: 'Pi',
          sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
          roomId: 'main',
          sessionId: rotatedSession,
        ),
      );
      await _settle();
      await _settle();

      final newRef = refFor(s.epk, rotatedSession);
      expect(LocalBoxes.msgsBoxName(newRef), isNot(oldBoxName));
      expect(messages(s.epk), isEmpty, reason: 'new session box starts empty');

      s.ch.push(UserInput(id: 'new-u1', text: 'new session row'));
      await _settle();

      expect(messages(s.epk, rotatedSession).map((row) => row.text), [
        'new session row',
      ]);
      expect(messages(s.epk, oldSession).map((row) => row.text), [
        'old session row',
      ]);
      expect(
        index(s.epk, rotatedSession)?.key,
        isNot(index(s.epk, oldSession)?.key),
      );
      expect(legacyBox.get(0), {
        'legacy': true,
      }, reason: 'old peer+room legacy cache box is not deleted');

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'runtime record does not report stale live state while disconnected',
    () async {
      final s = await setup();
      await _settle();
      RuntimeRecord runtime() {
        final raw = LocalBoxes().runtimeBox().get(
          LocalBoxes.runtimeKey(s.epk, 'main'),
        );
        return raw is Map
            ? RuntimeRecord.fromJson(raw.cast<String, dynamic>())
            : const RuntimeRecord();
      }

      expect(runtime().connection, RuntimeConnection.online);
      expect(runtime().presence, RuntimePresence.alive);

      final retrying = s.conn.statusStream.firstWhere(
        (status) => status is StatusRetrying,
      );
      await s.ch.close();
      await retrying;
      await _settle();

      expect(runtime().connection, isNot(RuntimeConnection.online));
      expect(runtime().presence, isNot(RuntimePresence.alive));
      expect(s.conn.isRoomWorking(s.epk, 'main'), isFalse);

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'foreign session_history is dropped before rows or index mutate',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'keep me'));
      await _settle();
      final beforeRows = [for (final m in messages(s.epk)) m.toJson()];
      final beforeIndex = index(s.epk);
      expect(beforeRows.map((m) => m['text']), ['keep me']);

      s.ch.pushRaw(
        SessionHistory(
          sessionId: 'foreign-session',
          inReplyTo: 'sync-foreign',
          sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
          events: const [UserInputEvt(ts: 1, id: 'foreign', text: 'drop me')],
          eos: true,
        ),
      );
      await _settle();

      expect([for (final m in messages(s.epk)) m.toJson()], beforeRows);
      expect(index(s.epk), beforeIndex);
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'missing session_id session_history is dropped before clearing rows',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'keep me'));
      await _settle();
      final beforeRows = [for (final m in messages(s.epk)) m.toJson()];
      final beforeIndex = index(s.epk);

      s.ch.pushRaw(
        SessionHistory(
          inReplyTo: 'sync-missing',
          sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
          events: const [UserInputEvt(ts: 2, id: 'missing', text: 'drop too')],
          eos: true,
        ),
      );
      await _settle();

      expect([for (final m in messages(s.epk)) m.toJson()], beforeRows);
      expect(index(s.epk), beforeIndex);
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('applyHistory defensively ignores bypassed foreign history', () async {
    final s = await setup();
    s.ch.push(UserInput(id: 'u1', text: 'keep me'));
    await _settle();
    final beforeRows = [for (final m in messages(s.epk)) m.toJson()];
    final beforeIndex = index(s.epk);

    await s.sync.debugApplyHistory(
      SessionHistory(
        sessionId: 'foreign-session',
        inReplyTo: 'direct-foreign',
        sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
        events: const [UserInputEvt(ts: 2, id: 'foreign', text: 'drop me')],
        eos: true,
      ),
    );
    await _settle();

    expect([for (final m in messages(s.epk)) m.toJson()], beforeRows);
    expect(index(s.epk), beforeIndex);
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'session gate drops foreign chunks, done, tools, queued, error, and compaction',
    () async {
      final s = await setup();
      const foreignSession = 'foreign-session';

      final foreignMessages = <ServerMessage>[
        AgentChunk(
          sessionId: foreignSession,
          inReplyTo: 'u1',
          delta: 'drop chunk',
        ),
        AgentDone(sessionId: foreignSession, inReplyTo: 'u1'),
        AgentMessage(
          sessionId: foreignSession,
          inReplyTo: 'u1',
          text: 'drop assistant',
        ),
        ToolRequest(
          sessionId: foreignSession,
          toolCallId: 'tool-foreign',
          tool: 'Read',
          args: const {'path': 'pubspec.yaml'},
        ),
        ToolResult(
          sessionId: foreignSession,
          toolCallId: 'tool-foreign',
          result: const {'ok': true},
        ),
        QueuedMessageState(
          sessionId: foreignSession,
          id: 'queued-foreign',
          text: 'drop queued',
        ),
        ErrorMessage(
          sessionId: foreignSession,
          inReplyTo: 'u1',
          code: 'internal_error',
          message: 'drop error',
        ),
        Compaction(
          sessionId: foreignSession,
          summary: 'drop compaction',
          tokensBefore: 123,
          ts: 1700000000000,
        ),
      ];

      for (final message in foreignMessages) {
        s.ch.pushRaw(message);
        await _settle();
      }

      expect(messages(s.epk), isEmpty);
      expect(index(s.epk), isNull);
      expect(s.sync.streaming, isNull);
      expect(s.sync.isWorking, isFalse);
      expect(s.sync.queuedText, isNull);
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'session gate drops foreign chunks while same-session chunks stream',
    () async {
      final s = await setup();
      s.ch.pushRaw(
        AgentChunk(
          sessionId: 'foreign-session',
          inReplyTo: 'u1',
          delta: 'drop',
        ),
      );
      await _settle();
      expect(s.sync.streaming, isNull);
      expect(s.sync.isWorking, isFalse);

      s.ch.pushRaw(
        AgentChunk(sessionId: s.sessionId, inReplyTo: 'u1', delta: 'keep'),
      );
      await _settle();
      expect(s.sync.streaming?.buffer, 'keep');
      expect(s.sync.isWorking, isTrue);
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('same-session reconnect history replay hydrates idempotently', () async {
    final s = await setup();
    const startedAt = 1_700_000_000;

    SessionHistory history(String inReplyTo) => SessionHistory(
      sessionId: s.sessionId,
      inReplyTo: inReplyTo,
      sessionStartedAt: startedAt,
      events: const [
        UserInputEvt(ts: 1, id: 'u1', text: 'hi'),
        AgentMessageEvt(ts: 2, inReplyTo: 'u1', text: 'done'),
        CompactionEvt(ts: 3, summary: 'compacted', tokensBefore: 5000),
      ],
      eos: true,
    );

    await s.sync.debugApplyHistory(history('sync-before-reconnect'));
    final afterFirstRows = [for (final m in messages(s.epk)) m.toJson()];
    final afterFirstIndex = index(s.epk);
    expect(afterFirstRows.map((m) => m['text']), ['hi', 'done', 'compacted']);

    final reconnect = _FakeChannel()..defaultSessionId = s.sessionId;
    s.conn.adopt(
      reconnect,
      PeerRecord(
        remoteEpk: s.epk,
        sessionName: 'Pi',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-01-01T00:00:00Z',
      ),
    );
    await _settle();
    reconnect.pushRaw(
      PairOk(
        inReplyTo: 'pair-reconnect',
        sessionName: 'Pi',
        sessionStartedAt: startedAt,
        roomId: 'main',
        sessionId: s.sessionId,
      ),
    );
    await _settle();
    await s.sync.debugApplyHistory(history('sync-after-reconnect'));

    expect([for (final m in messages(s.epk)) m.toJson()], afterFirstRows);
    expect(index(s.epk), afterFirstIndex);
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'replay diagnostics distinguish different events with one server timestamp',
    () async {
      final debugLog = _RecordingDebugLog();
      final s = await setup(debugLog: debugLog);

      s.ch.pushRaw(
        SessionHistory(
          sessionId: s.sessionId,
          inReplyTo: 'same-timestamp-replay',
          sessionStartedAt: 1,
          events: const [
            UserInputEvt(ts: 787455597602, id: 'u1', text: 'hi'),
            AgentMessageEvt(ts: 787455597602, inReplyTo: 'u1', text: 'done'),
          ],
          eos: true,
        ),
      );
      await _settle();

      final accepted = debugLog.events
          .whereType<ReplayDedupEvent>()
          .where((event) => !event.dropped)
          .toList();
      expect(accepted, hasLength(2));
      expect(
        accepted.map((event) => event.eventIdTail).toSet(),
        hasLength(2),
        reason: 'distinct event ids must not collide in the dedup oracle',
      );
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('interleaved history replays admit one durable event', () async {
    final store = _MemoryTranscriptStore();
    final debugLog = _RecordingDebugLog();
    final s = await setup(transcriptEventStore: store, debugLog: debugLog);
    final appendStarted = Completer<void>();
    final appendGate = Completer<void>();
    store.appendStarted = appendStarted;
    store.appendGate = appendGate;
    SessionHistory history(String requestId) => SessionHistory(
      sessionId: s.sessionId,
      inReplyTo: requestId,
      sessionStartedAt: 1,
      events: const [UserInputEvt(ts: 5, id: 'u1', text: 'once')],
      eos: true,
    );

    final first = s.sync.debugApplyHistory(history('replay-a'));
    await appendStarted.future;
    final second = s.sync.debugApplyHistory(history('replay-b'));
    appendGate.complete();
    await Future.wait([first, second]);

    expect(store.eventsFor(transcriptKeyFor(s.epk)), hasLength(1));
    expect(
      debugLog.events.whereType<ReplayDedupEvent>().map(
        (event) => event.dropped,
      ),
      [false, true],
    );
    s.conn.dispose();
    s.sync.dispose();
  });

  test('multi-batch history hydration emits one settled projection', () async {
    final store = _MemoryTranscriptStore();
    final s = await setup(transcriptEventStore: store);
    final appendStarted = Completer<void>();
    final appendGate = Completer<void>();
    store.appendStarted = appendStarted;
    store.appendGate = appendGate;
    final streamingEmissions = <StreamingMessage?>[];
    final sub = s.sync.streamingStream.listen(streamingEmissions.add);

    SessionHistory history(
      String requestId,
      List<SessionHistoryEvent> events,
    ) => SessionHistory(
      sessionId: s.sessionId,
      inReplyTo: requestId,
      sessionStartedAt: 1,
      events: events,
      eos: true,
    );

    final first = s.sync.debugApplyHistory(
      history('hydrate-1', const [
        UserInputEvt(ts: 1, id: 'hydrated-u1', text: 'replayed prompt'),
      ]),
    );
    await appendStarted.future;
    final second = s.sync.debugApplyHistory(
      history('hydrate-2', const [
        AgentMessageEvt(
          ts: 2,
          inReplyTo: 'hydrated-u1',
          text: 'complete replay',
        ),
      ]),
    );
    final third = s.sync.debugApplyHistory(
      history('hydrate-3', const [
        CompactionEvt(ts: 3, summary: 'summary', tokensBefore: 1000),
      ]),
    );
    appendGate.complete();
    await Future.wait([first, second, third]);
    await Future<void>.delayed(Duration.zero);

    expect(
      streamingEmissions,
      [isNull],
      reason: 'the hydration window publishes only its final projection',
    );
    expect(messages(s.epk).map((row) => row.text), [
      'replayed prompt',
      'complete replay',
      'summary',
    ]);
    expect(s.sync.streaming, isNull);
    expect(s.sync.isWorking, isFalse);

    await sub.cancel();
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'live deltas queued immediately after hydration still stream per frame',
    () async {
      final store = _MemoryTranscriptStore();
      final s = await setup(transcriptEventStore: store);
      final appendStarted = Completer<void>();
      final appendGate = Completer<void>();
      store.appendStarted = appendStarted;
      store.appendGate = appendGate;
      final streamingEmissions = <StreamingMessage?>[];
      final sub = s.sync.streamingStream.listen(streamingEmissions.add);

      final hydration = s.sync.debugApplyHistory(
        SessionHistory(
          sessionId: s.sessionId,
          inReplyTo: 'hydrate-before-live',
          sessionStartedAt: 1,
          events: const [
            UserInputEvt(ts: 1, id: 'live-u1', text: 'prompt'),
            AgentMessageEvt(
              ts: 2,
              inReplyTo: 'live-u1',
              text: 'older complete reply',
            ),
          ],
          eos: true,
        ),
      );
      await appendStarted.future;
      s.ch.pushRaw(
        AgentChunk(
          sessionId: s.sessionId,
          inReplyTo: 'live-u2',
          delta: 'live one',
        ),
      );
      s.ch.pushRaw(
        AgentChunk(
          sessionId: s.sessionId,
          inReplyTo: 'live-u2',
          delta: ' live two',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      appendGate.complete();
      await hydration;
      await _waitUntil(
        () => s.sync.streaming?.buffer == 'live one live two',
        reason: 'both live deltas to publish after hydration',
      );

      expect(
        streamingEmissions.where((emission) => emission == null),
        isEmpty,
        reason:
            'a newer live observation supersedes the stale hydration settle',
      );
      expect(
        streamingEmissions.whereType<StreamingMessage>().map(
          (message) => message.buffer,
        ),
        ['live one', 'live one live two'],
      );
      expect(s.sync.isWorking, isTrue);
      expect(s.sync.workingReplyTo, 'live-u2');
      expect(
        s.conn.isRoomWorking(s.epk, 'main'),
        isTrue,
        reason: 'the live turn remains authoritative after hydration settles',
      );

      await sub.cancel();
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'user_message echo writes one MessageRecord + updates the index',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'hi'));
      await _settle();

      final m = messages(s.epk);
      expect(m, hasLength(1));
      expect(m.first.role, MsgRole.user);
      expect(m.first.text, 'hi');
      expect(m.first.pending, isFalse);
      expect(index(s.epk)?.status, SessionActivity.working);
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'accepted tail append reads no log and writes one projection row',
    () async {
      final store = _MemoryTranscriptStore();
      final s = await setup(transcriptEventStore: store);
      final initialReads = store.readCalls;
      final box = LocalBoxes().openMsgsBox(refFor(s.epk));
      var rowWrites = 0;
      final subscription = box.watch().listen((_) => rowWrites++);

      s.ch.push(UserInput(id: 'delta-u1', text: 'one row'));
      await _settle();

      expect(store.readCalls, initialReads);
      expect(rowWrites, 1);
      expect(messages(s.epk).single.text, 'one row');

      await subscription.cancel();
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('optimistic send + echo dedupe → exactly one record', () async {
    final s = await setup();
    await s.sync.sendMessage('hello');
    await _settle();
    expect(messages(s.epk), hasLength(1));
    expect(messages(s.epk).first.pending, isTrue);

    final id = (s.ch.sent.whereType<UserMessage>().last).id;
    s.ch.push(UserInput(id: id, text: 'hello'));
    await _settle();

    final m = messages(s.epk);
    expect(m, hasLength(1), reason: 'echo dedupes by id — no duplicate');
    expect(m.first.pending, isFalse);
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'send diagnostics omit prompt and image content while wire and transcript retain it',
    () async {
      const promptCanary = 'prompt-secret-7F3A';
      const imageCanary = 'image-base64-secret-9D5E';
      const image = MessageImage(data: imageCanary, mime: 'image/png');
      final store = _MemoryTranscriptStore();
      final debugLog = _RecordingDebugLog();
      final console = <String>[];
      final originalDebugPrint = debugPrint;
      final s = await setup(transcriptEventStore: store, debugLog: debugLog);

      debugPrint = (message, {wrapWidth}) {
        if (message != null) console.add(message);
      };
      try {
        await s.sync.sendMessage(promptCanary, image: image);
        await s.sync.sendMessage('', image: image);
      } finally {
        debugPrint = originalDebugPrint;
      }

      final sent = s.ch.sent.whereType<UserMessage>().toList(growable: false);
      expect(sent, hasLength(2));
      expect(sent.first.text, promptCanary);
      expect(sent.first.images?.single.data, imageCanary);
      final submitted = store
          .eventsFor(transcriptKeyFor(s.epk))
          .whereType<UserMessageSubmitted>()
          .toList(growable: false);
      expect(submitted.map((event) => event.text), contains(promptCanary));
      expect(submitted.first.image?.data, imageCanary);

      final diagnostics = debugLog.events.whereType<MsgSendEvent>().toList(
        growable: false,
      );
      expect(diagnostics, hasLength(2));
      for (final event in diagnostics) {
        expect(
          event.toJson().keys,
          unorderedEquals(<String>['tag', 'ts', 'id', 'blocked']),
        );
      }
      final diagnosticText = <String>[
        ...console,
        ...diagnostics.map((event) => event.toJson().toString()),
      ].join('\n');
      expect(diagnosticText, isNot(contains(promptCanary)));
      expect(diagnosticText, isNot(contains(imageCanary)));
      expect(diagnosticText, isNot(contains('📷 Image')));

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'server failures retain user-visible text but omit it from diagnostics',
    () async {
      const secret = 'path=/Users/operator/workspace token=secret-7F3A';
      final store = _MemoryTranscriptStore();
      final debugLog = _RecordingDebugLog();
      final console = <String>[];
      final originalDebugPrint = debugPrint;
      final s = await setup(transcriptEventStore: store, debugLog: debugLog);

      debugPrint = (message, {wrapWidth}) {
        if (message != null) console.add(message);
      };
      try {
        await s.sync.sendMessage('known failure');
        final knownId = s.ch.sent.whereType<UserMessage>().last.id;
        s.ch.push(
          ErrorMessage(
            sessionId: s.sessionId,
            inReplyTo: knownId,
            code: 'internal_error',
            message: secret,
          ),
        );
        await _waitUntil(
          () => store
              .eventsFor(transcriptKeyFor(s.epk))
              .whereType<UserMessageFailed>()
              .any((event) => event.clientMessageId == knownId),
          reason: 'known server failure is persisted for transcript projection',
        );

        await s.sync.sendMessage('unknown failure');
        final unknownId = s.ch.sent.whereType<UserMessage>().last.id;
        s.ch.push(
          ErrorMessage(
            sessionId: s.sessionId,
            inReplyTo: unknownId,
            code: 'future_error_code',
            message: secret,
          ),
        );
        await _waitUntil(
          () => debugLog.events.whereType<MsgFailedEvent>().length == 2,
          reason: 'both diagnostic projections are captured',
        );
      } finally {
        debugPrint = originalDebugPrint;
      }

      final failures = store
          .eventsFor(transcriptKeyFor(s.epk))
          .whereType<UserMessageFailed>()
          .toList(growable: false);
      expect(failures, hasLength(2));
      expect(failures.map((event) => event.message), everyElement(secret));

      final diagnostics = debugLog.events.whereType<MsgFailedEvent>().toList(
        growable: false,
      );
      expect(diagnostics.map((event) => event.toJson()['code']), [
        'internal_error',
        kUnrecognizedFailureCode,
      ]);
      final diagnosticText = <String>[
        ...console,
        ...diagnostics.map((event) => event.toJson().toString()),
      ].join('\n');
      expect(diagnosticText, isNot(contains(secret)));
      expect(diagnosticText, isNot(contains('/Users/operator/workspace')));
      expect(diagnosticText, isNot(contains('token=secret-7F3A')));

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'steer send keeps active working target and sets streaming behavior on wire',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'primary'));
      await _settle();

      await s.sync.sendMessage(
        'refine this',
        streamingBehavior: UserMessageStreamingBehavior.steer,
      );
      await _settle();

      final sent = s.ch.sent.whereType<UserMessage>().lastWhere(
        (m) => m.text == 'refine this',
      );
      expect(sent.streamingBehavior, UserMessageStreamingBehavior.steer);
      expect(s.sync.workingReplyTo, 'u1');
      expect(s.sync.streaming, isNotNull);
      expect(s.sync.streaming!.inReplyTo, 'u1');
      expect(s.sync.isWorking, isTrue);

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('steer echo confirms row without replacing working turn', () async {
    final s = await setup();
    s.ch.push(UserInput(id: 'u1', text: 'primary'));
    await _settle();
    expect(s.sync.workingReplyTo, 'u1');

    await s.sync.sendMessage(
      'refine this',
      streamingBehavior: UserMessageStreamingBehavior.steer,
    );
    await _settle();
    final sent = s.ch.sent.whereType<UserMessage>().lastWhere(
      (m) => m.text == 'refine this',
    );

    s.ch.push(
      UserInput(
        id: sent.id,
        text: 'refine this',
        streamingBehavior: UserMessageStreamingBehavior.steer,
      ),
    );
    await _settle();

    expect(s.sync.workingReplyTo, 'u1');
    expect(s.sync.streaming, isNotNull);
    expect(s.sync.streaming!.inReplyTo, 'u1');
    expect(s.sync.isWorking, isTrue);
    var rows = messages(s.epk);
    expect(
      rows.map((row) => row.id),
      ['u1'],
      reason: 'delivery acceptance must not anchor the steering bubble',
    );
    expect(
      s.sync.steeringProjection,
      SteeringPending(clientMessageId: sent.id, text: 'refine this'),
    );

    s.ch.push(
      UserInput(
        id: sent.id,
        text: 'refine this',
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _settle();

    rows = messages(s.epk);
    expect(rows.map((row) => row.id), ['u1', sent.id]);
    expect(rows.where((r) => r.id == sent.id).single.pending, isFalse);
    expect(s.sync.steeringProjection, isA<NoSteering>());
    expect(index(s.epk)?.status, SessionActivity.working);
    expect(index(s.epk)?.lastMessagePreview, 'refine this');

    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'correlated steering rejection clears pending and shows one failed row',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'primary'));
      await _waitUntil(
        () => s.sync.workingReplyTo == 'u1',
        reason: 'primary turn activation before steering rejection',
      );
      s.ch.push(AgentChunk(inReplyTo: 'u1', delta: 'primary partial'));
      await _waitUntil(
        () => s.sync.streaming?.buffer == 'primary partial',
        reason: 'primary streaming buffer before steering rejection',
      );

      await s.sync.sendMessage(
        'bad steer',
        streamingBehavior: UserMessageStreamingBehavior.steer,
      );
      final sent = s.ch.sent.whereType<UserMessage>().last;
      expect(s.sync.steeringProjection, isA<SteeringPending>());

      s.ch.push(
        ErrorMessage(
          sessionId: s.sessionId,
          inReplyTo: sent.id,
          code: 'internal_error',
          message: 'steer rejected',
        ),
      );
      await _waitUntil(
        () =>
            s.sync.steeringProjection is NoSteering &&
            messages(s.epk).any(
              (row) => row.id == sent.id && row.status == UserMsgStatus.failed,
            ),
        reason: 'correlated steering rejection convergence',
      );

      expect(s.sync.workingReplyTo, 'u1');
      expect(s.sync.streaming?.inReplyTo, 'u1');
      expect(s.sync.streaming?.buffer, 'primary partial');
      expect(s.sync.isWorking, isTrue);
      final failed = messages(
        s.epk,
      ).where((row) => row.id == sent.id).toList(growable: false);
      expect(failed, hasLength(1));
      expect(failed.single.status, UserMsgStatus.failed);

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'failed steering rejection persistence still clears only the overlay',
    () async {
      final store = _MemoryTranscriptStore();
      final s = await setup(transcriptEventStore: store);
      s.ch.push(UserInput(id: 'u1', text: 'primary'));
      await _waitUntil(
        () => s.sync.workingReplyTo == 'u1',
        reason: 'primary turn activation before failed rejection append',
      );
      s.ch.push(AgentChunk(inReplyTo: 'u1', delta: 'primary partial'));
      await _waitUntil(
        () => s.sync.streaming?.buffer == 'primary partial',
        reason: 'primary stream before failed rejection append',
      );

      await s.sync.sendMessage(
        'bad steer',
        streamingBehavior: UserMessageStreamingBehavior.steer,
      );
      final sent = s.ch.sent.whereType<UserMessage>().last;
      expect(s.sync.steeringProjection, isA<SteeringPending>());

      store.failNextAppend = true;
      s.ch.push(
        ErrorMessage(
          sessionId: s.sessionId,
          inReplyTo: sent.id,
          code: 'internal_error',
          message: 'steer rejected',
        ),
      );
      await _waitUntil(
        () => s.sync.steeringProjection is NoSteering,
        reason: 'persistence-independent steering rejection convergence',
      );

      expect(s.sync.workingReplyTo, 'u1');
      expect(s.sync.streaming?.inReplyTo, 'u1');
      expect(s.sync.streaming?.buffer, 'primary partial');
      expect(s.sync.isWorking, isTrue);

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('streaming delta does NOT write to the DB (#7)', () async {
    final s = await setup();
    final before = messages(s.epk).length;
    s.ch.push(AgentChunk(inReplyTo: 'r1', delta: 'partial...'));
    await _settle();
    expect(messages(s.epk).length, before, reason: 'no row for a delta');
    expect(s.sync.streaming, isNotNull);
    expect(s.sync.streaming!.buffer, 'partial...');
    s.conn.dispose();
    s.sync.dispose();
  });

  test('agent_done finalizes the streamed message + flips to idle', () async {
    final s = await setup();
    s.ch.push(AgentChunk(inReplyTo: 'r1', delta: 'done text'));
    await _settle();
    s.ch.push(AgentDone(inReplyTo: 'r1'));
    await _settle();

    final assistant = messages(
      s.epk,
    ).where((m) => m.role == MsgRole.assistant).toList();
    expect(assistant, hasLength(1));
    expect(assistant.first.text, 'done text');
    expect(s.sync.streaming, isNull);
    expect(index(s.epk)?.status, SessionActivity.idle);
    s.conn.dispose();
    s.sync.dispose();
  });

  test('legacy streamed assistant commit uses agent_done server ts', () async {
    final store = _MemoryTranscriptStore();
    final s = await setup(transcriptEventStore: store);
    const canonicalTs = 4242;

    s.ch.push(const AgentChunk(inReplyTo: 'r-ts', delta: 'server-timed text'));
    await _settle();
    s.ch.push(const AgentDone(inReplyTo: 'r-ts', ts: canonicalTs));
    await _settle();

    final committed = store
        .eventsFor(transcriptKeyFor(s.epk))
        .whereType<AssistantMessageCommitted>()
        .single;
    expect(committed.ts, DateTime.fromMillisecondsSinceEpoch(canonicalTs));
    expect(committed.text, 'server-timed text');
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'live tool frames consume server ts and fall back for legacy frames',
    () async {
      final store = _MemoryTranscriptStore();
      final s = await setup(transcriptEventStore: store);
      const requestTs = 1_700_000_000_123;
      const resultTs = 1_700_000_000_456;

      s.ch.pushRaw(
        ToolRequest(
          sessionId: s.sessionId,
          toolCallId: 'tool-with-ts',
          tool: 'Read',
          args: const {'path': 'pubspec.yaml'},
          ts: requestTs,
        ),
      );
      await _settle();
      s.ch.pushRaw(
        ToolResult(
          sessionId: s.sessionId,
          toolCallId: 'tool-with-ts',
          result: const {'ok': true},
          ts: resultTs,
        ),
      );
      await _settle();

      final requestedWithTs = store
          .eventsFor(transcriptKeyFor(s.epk))
          .whereType<ToolRequested>()
          .single;
      final finishedWithTs = store
          .eventsFor(transcriptKeyFor(s.epk))
          .whereType<ToolFinished>()
          .single;
      expect(
        requestedWithTs.ts,
        DateTime.fromMillisecondsSinceEpoch(requestTs),
      );
      expect(finishedWithTs.ts, DateTime.fromMillisecondsSinceEpoch(resultTs));

      final requestBefore = DateTime.now();
      s.ch.push(
        ToolRequest(toolCallId: 'tool-without-ts', tool: 'Read', args: {}),
      );
      await _settle();
      final requestAfter = DateTime.now();
      final resultBefore = DateTime.now();
      s.ch.push(ToolResult(toolCallId: 'tool-without-ts', result: 'ok'));
      await _settle();
      final resultAfter = DateTime.now();

      final requestedWithoutTs = store
          .eventsFor(transcriptKeyFor(s.epk))
          .whereType<ToolRequested>()
          .singleWhere((event) => event.toolCallId == 'tool-without-ts');
      final finishedWithoutTs = store
          .eventsFor(transcriptKeyFor(s.epk))
          .whereType<ToolFinished>()
          .singleWhere((event) => event.toolCallId == 'tool-without-ts');
      expect(requestedWithoutTs.ts.isBefore(requestBefore), isFalse);
      expect(requestedWithoutTs.ts.isAfter(requestAfter), isFalse);
      expect(finishedWithoutTs.ts.isBefore(resultBefore), isFalse);
      expect(finishedWithoutTs.ts.isAfter(resultAfter), isFalse);

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('error diagnostics consume canonical ts and retain mixed-era fallback', () async {
    final store = _MemoryTranscriptStore();
    final s = await setup(transcriptEventStore: store);
    const canonicalTs = 1_700_000_001_234;

    s.ch.push(
      ErrorMessage(
        sessionId: s.sessionId,
        inReplyTo: 'canonical-error',
        code: 'provider_error',
        message: 'server timed',
        ts: canonicalTs,
      ),
    );
    await _settle();

    final fallbackBefore = DateTime.now();
    s.ch.push(
      ErrorMessage(
        sessionId: s.sessionId,
        inReplyTo: 'legacy-error',
        code: 'internal_error',
        message: 'legacy timed',
      ),
    );
    await _settle();
    final fallbackAfter = DateTime.now();

    final diagnostics = store
        .eventsFor(transcriptKeyFor(s.epk))
        .whereType<AssistantMessageCommitted>()
        .where((event) => event.text.startsWith('⚠'))
        .toList();
    final canonical = diagnostics.singleWhere(
      (event) => event.text.contains('server timed'),
    );
    final legacy = diagnostics.singleWhere(
      (event) => event.text.contains('legacy timed'),
    );
    expect(canonical.ts, DateTime.fromMillisecondsSinceEpoch(canonicalTs));
    expect(legacy.ts.isBefore(fallbackBefore), isFalse);
    expect(legacy.ts.isAfter(fallbackAfter), isFalse);

    s.conn.dispose();
    s.sync.dispose();
  });

  test('cancel sends a Cancel frame for the active turn target', () async {
    final s = await setup();
    s.ch.push(UserInput(id: 'u1', text: 'hi'));
    await _settle();

    await s.sync.cancel('u1');
    await _settle();

    final cancel = s.ch.sent.whereType<Cancel>().single;
    expect(cancel.targetId, 'u1');
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'cancelled stops the turn but preserves confirmed user history',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'keep this'));
      await _settle();
      s.ch.push(AgentChunk(inReplyTo: 'u1', delta: 'partial'));
      s.ch.push(Cancelled(inReplyTo: 'cancel-1', targetId: 'u1'));
      await _settle();

      final rows = messages(s.epk);
      expect(
        rows.where((m) => m.id == 'u1' && m.role == MsgRole.user),
        hasLength(1),
      );
      expect(rows.singleWhere((m) => m.id == 'u1').pending, isFalse);
      expect(s.sync.streaming, isNull);
      expect(s.sync.isWorking, isFalse);
      expect(index(s.epk)?.status, SessionActivity.idle);
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('cancelled terminalizes a separately pending steering prompt', () async {
    final store = _MemoryTranscriptStore();
    final s = await setup(transcriptEventStore: store);
    s.ch.push(UserInput(id: 'u1', text: 'primary'));
    await _waitUntil(
      () => s.sync.workingReplyTo == 'u1',
      reason: 'primary turn activation before cancel',
    );

    await s.sync.sendMessage(
      'queued refinement',
      streamingBehavior: UserMessageStreamingBehavior.steer,
    );
    final steerId = s.ch.sent.whereType<UserMessage>().last.id;
    s.ch.push(
      UserInput(
        id: steerId,
        text: 'queued refinement',
        streamingBehavior: UserMessageStreamingBehavior.steer,
      ),
    );
    await _waitUntil(
      () =>
          s.sync.steeringProjection ==
          SteeringPending(clientMessageId: steerId, text: 'queued refinement'),
      reason: 'accepted steering overlay before cancel',
    );
    expect(
      s.sync.steeringProjection,
      SteeringPending(clientMessageId: steerId, text: 'queued refinement'),
    );

    s.ch.push(Cancelled(inReplyTo: 'cancel-1', targetId: 'u1'));
    await _waitUntil(
      () =>
          s.sync.steeringProjection is NoSteering &&
          store
              .eventsFor(transcriptKeyFor(s.epk))
              .whereType<UserMessageFailed>()
              .any((event) => event.clientMessageId == steerId) &&
          messages(s.epk).any(
            (row) => row.id == steerId && row.status == UserMsgStatus.failed,
          ),
      reason: 'cancelled steering durable terminal convergence',
    );

    expect(s.sync.steeringProjection, isA<NoSteering>());
    expect(s.sync.isWorking, isFalse);
    final failures = store
        .eventsFor(transcriptKeyFor(s.epk))
        .whereType<UserMessageFailed>()
        .where((event) => event.clientMessageId == steerId);
    expect(failures, hasLength(1));
    expect(failures.single.code, 'cancelled');
    expect(
      deriveTranscriptProjection(
        sessionId: s.sessionId,
        events: store.eventsFor(transcriptKeyFor(s.epk)),
      ).steering,
      isA<NoSteering>(),
    );
    expect(
      messages(s.epk).singleWhere((row) => row.id == steerId).status,
      UserMsgStatus.failed,
    );

    s.conn.dispose();
    s.sync.dispose();
  });

  test('cancelled marks a still-pending optimistic user row failed', () async {
    final s = await setup();
    await s.sync.sendMessage('stop before echo');
    await _settle();
    final id = (s.ch.sent.whereType<UserMessage>().last).id;
    expect(messages(s.epk).single.pending, isTrue);

    s.ch.push(Cancelled(inReplyTo: 'cancel-1', targetId: id));
    await _settle();

    final rows = messages(s.epk);
    expect(rows, hasLength(1));
    expect(rows.single.id, id);
    expect(rows.single.role, MsgRole.user);
    expect(rows.single.status, UserMsgStatus.failed);
    expect(s.sync.streaming, isNull);
    expect(s.sync.isWorking, isFalse);
    expect(index(s.epk)?.status, SessionActivity.idle);
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'server error clears pending chunk flush so chat does not stay working',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'hi'));
      await _settle();
      s.ch.push(AgentChunk(inReplyTo: 'u1', delta: 'partial'));
      s.ch.push(
        ErrorMessage(
          inReplyTo: 'cancel-1',
          code: 'internal_error',
          message: 'No active Pi context to abort',
        ),
      );
      await _settle();

      expect(s.sync.streaming, isNull);
      expect(s.sync.isWorking, isFalse);
      expect(index(s.epk)?.status, SessionActivity.idle);
      final errorTexts = messages(
        s.epk,
      ).where((m) => m.role == MsgRole.assistant).map((m) => m.text);
      expect(errorTexts, contains(startsWith('⚠ internal_error:')));
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('isWorking spans the whole turn (echo → agent_done)', () async {
    final s = await setup();
    expect(s.sync.isWorking, isFalse);
    final flags = <bool>[];
    final sub = s.sync.workingStream.listen(flags.add);

    s.ch.push(UserInput(id: 'u1', text: 'hi'));
    await _settle();
    expect(s.sync.isWorking, isTrue, reason: 'working from the echo');

    s.ch.push(AgentDone(inReplyTo: 'u1'));
    await _settle();
    expect(s.sync.isWorking, isFalse, reason: 'idle after agent_done');
    expect(flags, [true, false]);

    await sub.cancel();
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'late duplicate user echo cannot reopen working after a newer idle snapshot',
    () async {
      final s = await setup();

      s.ch.push(UserInput(id: 'turn-one', text: 'first turn'));
      await _settle();
      expect(s.conn.isRoomWorking(s.epk, 'main'), isTrue);

      s.ch.pushControl(
        RoomsSnapshot(
          peer: s.epk,
          rooms: [
            RoomInfo(
              roomId: 'main',
              sessionId: s.sessionId,
              startedAt: 1,
              working: false,
            ),
          ],
        ),
      );
      await _settle();
      expect(s.conn.isRoomWorking(s.epk, 'main'), isFalse);

      s.ch.push(UserInput(id: 'turn-one', text: 'first turn'));
      await _settle();
      expect(
        s.conn.isRoomWorking(s.epk, 'main'),
        isFalse,
        reason: 'the duplicate belongs to the turn closed by the snapshot',
      );

      s.ch.push(UserInput(id: 'turn-two', text: 'next turn'));
      await _settle();
      expect(
        s.conn.isRoomWorking(s.epk, 'main'),
        isTrue,
        reason: 'a distinct newer turn may open the working backstop',
      );

      s.ch.push(AgentDone(inReplyTo: 'turn-two'));
      await _settle();
      expect(s.conn.isRoomWorking(s.epk, 'main'), isFalse);
      s.ch.push(UserInput(id: 'turn-two', text: 'next turn'));
      await _settle();
      expect(
        s.conn.isRoomWorking(s.epk, 'main'),
        isFalse,
        reason: 'a local terminal correction also fences its completed turn',
      );

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'late session_history after terminal false does not reopen working or cancel target',
    () async {
      final s = await setup();

      s.ch.push(UserInput(id: 'late-u1', text: 'from late attach'));
      await _settle();
      expect(s.sync.isWorking, isTrue);
      expect(s.sync.workingReplyTo, 'late-u1');
      expect(s.conn.isRoomWorking(s.epk, 'main'), isTrue);

      s.ch.push(AgentChunk(inReplyTo: 'late-u1', delta: 'final text'));
      await _settle();
      s.ch.push(AgentDone(inReplyTo: 'late-u1'));
      await _settle();
      expect(s.sync.isWorking, isFalse);
      expect(s.sync.workingReplyTo, isNull);
      expect(s.sync.streaming, isNull);
      expect(s.conn.isRoomWorking(s.epk, 'main'), isFalse);

      s.ch.pushRaw(
        SessionHistory(
          sessionId: s.sessionId,
          inReplyTo: 'late-u1',
          sessionStartedAt: 1,
          events: const [
            UserInputEvt(ts: 1, id: 'late-u1', text: 'from late attach'),
            AgentMessageEvt(ts: 2, inReplyTo: 'late-u1', text: 'final text'),
          ],
          eos: true,
          truncated: false,
        ),
      );
      await _settle();

      expect(s.sync.isWorking, isFalse);
      expect(s.sync.workingReplyTo, isNull);
      expect(s.sync.streaming, isNull);
      expect(s.conn.isRoomWorking(s.epk, 'main'), isFalse);
      expect(index(s.epk)?.status, SessionActivity.idle);

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'disconnect while online keeps pending backstops and avoids stuck bubbles',
    () async {
      const short = Duration.zero;
      final s = await setup(pendingSendTimeout: short);
      final status = s.conn.statusStream.firstWhere(
        (status) => status is StatusRetrying,
      );

      await s.sync.setQueuedMessage('draft');
      await s.sync.sendMessage('hi');

      expect(s.sync.queuedText, 'draft');
      expect(
        s.sync.isWorking,
        isTrue,
        reason: 'online send enters whole-turn working',
      );
      expect(s.sync.streaming, isNotNull, reason: 'online send seeds cursor');
      expect(s.sync.workingReplyTo, isNotNull);
      expect(
        s.sync.debugPendingSendTimerCount,
        1,
        reason: 'send timeout timer is armed',
      );
      final before = messages(s.epk);
      expect(before, hasLength(1), reason: 'optimistic pending row is written');
      expect(before.first.pending, isTrue);

      await s.ch.close();
      expect(
        await status,
        isA<StatusRetrying>(),
        reason: 'disconnect transitions to retrying',
      );
      expect(s.sync.isWorking, isFalse, reason: 'status drop clears working');
      expect(s.sync.streaming, isNull, reason: 'streaming cursor is cleared');
      expect(
        s.sync.workingReplyTo,
        isNull,
        reason: 'stale cancel target cleared',
      );
      expect(s.sync.queuedText, isNull, reason: 'queued text is cleared');
      expect(
        s.sync.debugPendingSendTimerCount,
        1,
        reason: 'disconnect keeps pending-send backstops alive',
      );

      List<MessageRecord> failed = messages(s.epk);
      for (var i = 0; i < 1000; i++) {
        if (failed.length == 1 && failed.single.pending == false) {
          break;
        }
        await Future<void>.delayed(Duration.zero);
        failed = messages(s.epk);
      }
      if (failed.length != 1 || failed.first.pending == true) {
        fail(
          'timed out waiting for pending-send timeout row to fail after $short',
        );
      }
      expect(
        failed,
        hasLength(1),
        reason: 'pending row converges to visible failure',
      );
      expect(failed.single.role, MsgRole.user);
      expect(failed.single.status, UserMsgStatus.failed);
      expect(failed.single.text, 'hi');
      expect(s.sync.debugPendingSendTimerCount, 0);

      final reconnect = _FakeChannel();
      s.conn.adopt(
        reconnect,
        PeerRecord(
          remoteEpk: s.epk,
          sessionName: 'Pi',
          relayUrl: 'ws://localhost',
          pairedAt: '2026-01-01T00:00:00Z',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        messages(s.epk).single.pending,
        isFalse,
        reason: 'reconnect does not leave a stuck pending row',
      );

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('switching sessions resets the in-memory turn state — working/streaming '
      'do NOT leak into the next chat (plan/32)', () async {
    final s = await setup();

    // Session 1 is mid-turn: working flag + streaming buffer populated.
    s.ch.push(AgentChunk(inReplyTo: 'r1', delta: 'thinking...'));
    await _waitUntil(
      () => s.sync.streaming?.buffer == 'thinking...',
      reason: 'the first session chunk projection',
    );
    expect(s.sync.isWorking, isTrue);
    expect(s.sync.streaming, isNotNull);
    expect(s.sync.workingReplyTo, 'r1');

    final flags = <bool>[];
    final sub = s.sync.workingStream.listen(flags.add);

    // Switch the writer to a DIFFERENT session (what the chat does on a
    // tablet session switch). Must clear the in-memory signals.
    await s.sync.activate('epk_other_session', 'main');
    await _settle();

    expect(
      s.sync.isWorking,
      isFalse,
      reason: 'chat 2 must not inherit chat 1 working',
    );
    expect(
      s.sync.streaming,
      isNull,
      reason: 'chat 1 streaming buffer must not show in chat 2',
    );
    expect(s.sync.workingReplyTo, isNull);
    expect(
      flags,
      contains(false),
      reason: 'listeners are notified the flag cleared',
    );

    // The previous session's DURABLE index must stay "working" — the Pi
    // may still be mid-turn and Home reflects it (relay broadcast + DB).
    // Clearing the in-memory signals must NOT idle the box row.
    expect(
      index(s.epk)?.status,
      SessionActivity.working,
      reason: 'switching away must not idle chat 1 in the DB',
    );

    await sub.cancel();
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'cursor: streaming is seeded EMPTY at turn start, before any chunk',
    () async {
      final s = await setup();
      expect(s.sync.streaming, isNull);

      // Optimistic send seeds the thinking cursor (online).
      await s.sync.sendMessage('hi');
      await _settle();
      expect(s.sync.streaming, isNotNull, reason: 'cursor during thinking');
      expect(s.sync.streaming!.buffer, isEmpty);

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'cursor: foreign echo seeds it; a text-less turn clears it on done',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u9', text: 'from terminal'));
      await _settle();
      expect(s.sync.streaming, isNotNull, reason: 'cursor before any chunk');
      expect(s.sync.streaming!.buffer, isEmpty);

      // Turn produces no text (e.g. only tool calls) → done still clears it.
      s.ch.push(AgentDone(inReplyTo: 'u9'));
      await _settle();
      expect(s.sync.streaming, isNull, reason: 'done clears the cursor');
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('cursor: a chunk appends onto the seeded empty buffer', () async {
    final s = await setup();
    s.ch.push(UserInput(id: 'u1', text: 'hi'));
    await _settle();
    s.ch.push(AgentChunk(inReplyTo: 'u1', delta: 'tok'));
    await _settle();
    expect(s.sync.streaming!.buffer, 'tok', reason: 'appended, not replaced');
    s.conn.dispose();
    s.sync.dispose();
  });

  // Regression for `story-mobile-assistant-message-duplicated-live-replay` decision 2.
  // The ToolRequest pre-tool flush is fire-and-forget; if a second ToolRequest
  // arrives before the async projection write resolves, the in-memory
  // _streaming buffer was not yet cleared, so the SAME buffered text was
  // re-committed under a new random eventId → ×N duplicate assistant rows
  // (the ×4-on-first-paragraph amplification). The fix clears the buffer
  // synchronously at flush time so the second flush sees an empty buffer.
  test(
    'ToolRequest flush is not re-amplified: two tool requests before the async '
    'projection resolves commit the buffered text once',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'go'));
      await _settle();
      s.ch.push(AgentChunk(inReplyTo: 'u1', delta: 'shared text'));
      await _settle(); // buffer settles into _streaming
      // Two tool requests in the SAME sync tick — the async projection from
      // the first flush has not resolved, so the second flush would re-read
      // the un-cleared buffer and commit 'shared text' a second time.
      s.ch.push(ToolRequest(toolCallId: 'tc1', tool: 'Read', args: {}));
      s.ch.push(ToolRequest(toolCallId: 'tc2', tool: 'Grep', args: {}));
      await _settle();
      await _settle();
      s.ch.push(AgentDone(inReplyTo: 'u1'));
      await _settle();

      final assistantRows = messages(
        s.epk,
      ).where((r) => r.role == MsgRole.assistant).toList();
      final shared = assistantRows.where((r) => r.text == 'shared text');
      expect(
        shared.length,
        1,
        reason:
            'The buffered text must be committed exactly once even when two '
            'ToolRequests fire before the async projection resolves. Previously '
            'the second flush re-committed the same buffer under a new random '
            'eventId (the ×N amplification root cause).',
      );
      final toolRows = messages(
        s.epk,
      ).where((r) => r.role == MsgRole.tool).toList();
      expect(toolRows.length, 2, reason: 'both tool calls are recorded');
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  // Regression for `story-mobile-assistant-message-duplicated-live-replay`
  // decision 1 (identity source (a)). A live `agent_message` carrying the
  // SDK `ts` must commit with the SAME deterministic eventId as the
  // `AgentMessageEvt` replay path, so a live commit + a replay of the same
  // assistant message collapse to ONE Hive row (deduped by eventId) instead
  // of two rows with incompatible random-vs-deterministic ids.
  test(
    'live agent_message(ts) + replay AgentMessageEvt collapse to one row',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'hi'));
      await _settle();
      // Live assistant message carrying the SDK ts (the extension's
      // message_end-driven broadcast). Commits with a deterministic eventId.
      const liveTs = 2000;
      s.ch.push(
        const AgentMessage(inReplyTo: 'u1', text: 'hello back', ts: liveTs),
      );
      await _settle();
      final afterLive = messages(
        s.epk,
      ).where((r) => r.role == MsgRole.assistant).length;
      expect(afterLive, 1, reason: 'live agent_message commits one row');

      // Replay the SAME assistant message via session_history. Under the
      // old random-id live scheme this would add a SECOND row (incompatible
      // eventIds). With deterministic identity it must collapse.
      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync1',
          sessionStartedAt: 0,
          events: const [
            UserInputEvt(ts: 1, id: 'u1', text: 'hi'),
            AgentMessageEvt(ts: liveTs, inReplyTo: 'u1', text: 'hello back'),
          ],
          eos: true,
        ),
      );
      await _settle();

      final assistantRows = messages(
        s.epk,
      ).where((r) => r.role == MsgRole.assistant).toList();
      expect(
        assistantRows.length,
        1,
        reason:
            'A live agent_message(ts) and a replay AgentMessageEvt for the '
            'same (inReplyTo, ts) must collapse to one row. Previously the '
            'live path used a random eventId while replay used a '
            'deterministic one, so both survived as distinct Hive rows '
            '→ duplicate assistant bubble.',
      );
      expect(assistantRows.single.text, 'hello back');
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  // Regression for the ToolRequest-flush duplication. The SDK fires
  // `message_end` (→ extension broadcasts `agent_message(ts)`) BEFORE
  // `tool_execution_start` (→ app receives `ToolRequest`). So the
  // deterministic `agent_message(ts)` commit lands first and sets
  // `_agentMessageCommittedThisTurn`. The `ToolRequest` handler must NOT
  // re-commit the streaming buffer under a random eventId — that would
  // duplicate the text as a second row (random-uuid live row + deterministic
  // replay row = the visible dupe). Mirrors the `AgentDone` skip. See
  // story-mobile-assistant-message-duplicated-live-replay decision 1.
  test(
    'ToolRequest after agent_message(ts) does not re-commit the buffer',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'go'));
      await _settle();
      // Stream some text into the buffer.
      s.ch.push(const AgentChunk(inReplyTo: 'u1', delta: 'narration text'));
      await _settle();
      // Live agent_message(ts) from message_end — commits deterministically.
      const liveTs = 2000;
      s.ch.push(
        const AgentMessage(inReplyTo: 'u1', text: 'narration text', ts: liveTs),
      );
      await _settle();
      // ToolRequest arrives AFTER the deterministic commit. Under the old
      // code this re-committed the buffer with a random uuid → second row.
      s.ch.push(const ToolRequest(toolCallId: 'tc1', tool: 'Read', args: {}));
      await _settle();
      s.ch.push(AgentDone(inReplyTo: 'u1'));
      await _settle();

      final assistantRows = messages(
        s.epk,
      ).where((r) => r.role == MsgRole.assistant).toList();
      final narration = assistantRows.where((r) => r.text == 'narration text');
      expect(
        narration.length,
        1,
        reason:
            'The buffered text must be committed exactly once. The '
            'deterministic agent_message(ts) commit from message_end lands '
            'before ToolRequest; the ToolRequest flush must not re-commit '
            'the same text under a random eventId (the live×replay dupe).',
      );
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  // Layer 2 of story-mobile-connection-flapping-drops-identity-frames.
  // The relay's fan-out suspend (story-extension-suspend-fanout-on-peer-
  // offline) DROPS frames for an offline peer rather than queueing them.
  // If the deterministic `agent_message(ts)` frame (the single source of
  // live assistant identity) is dropped during a flap in the
  // message_end→tool_execution_start window, the ToolRequest/AgentDone
  // fallback would commit the streamed buffer under a random uuid. That
  // random-id live row then dupes against the deterministic replay row
  // that arrives on the reconnect session_sync → visible duplicate bubble.
  //
  // Fix: once the app has seen a live agent_message(ts) at least once
  // (capability latched), a later turn with NO agent_message(ts) at flush
  // time is treated as a dropped frame, not a legacy extension. The
  // random-uuid fallback is SUPPRESSED; the reconnect replay fills the row
  // deterministically. This test simulates the dropped-frame turn by NOT
  // sending agent_message(ts), then delivering the replay.
  test('dropped agent_message(ts) mid-flap: ToolRequest/AgentDone suppress '
      'random-uuid fallback; replay fills deterministically', () async {
    final s = await setup();
    s.ch.push(UserInput(id: 'u1', text: 'go'));
    await _settle();
    // Latch the capability: a PRIOR turn delivered agent_message(ts),
    // proving the extension emits deterministic identity frames.
    const priorTs = 1000;
    s.ch.push(
      const AgentMessage(inReplyTo: 'u1', text: 'prior turn text', ts: priorTs),
    );
    await _settle();
    s.ch.push(AgentDone(inReplyTo: 'u1'));
    await _settle();

    // Next turn: the agent_message(ts) frame is DROPPED (flap hit during
    // message_end→tool_execution_start). Only streaming chunks + the
    // ToolRequest arrive.
    s.ch.push(UserInput(id: 'u2', text: 'next'));
    await _settle();
    s.ch.push(const AgentChunk(inReplyTo: 'u2', delta: 'narration text'));
    await _settle();
    // No agent_message(ts) arrives — it was dropped.
    s.ch.push(const ToolRequest(toolCallId: 'tc1', tool: 'Read', args: {}));
    await _settle();
    s.ch.push(AgentDone(inReplyTo: 'u2'));
    await _settle();

    // Before the replay: the dropped-frame turn must NOT have committed a
    // random-uuid row for 'narration text'.
    final beforeReplay = messages(
      s.epk,
    ).where((r) => r.text == 'narration text');
    expect(
      beforeReplay,
      isEmpty,
      reason:
          'The dropped agent_message(ts) frame must not trigger a '
          'random-uuid fallback commit (it would dupe against the replay).',
    );

    // Reconnect session_sync delivers the deterministic replay for the
    // dropped turn.
    const liveTs = 2000;
    s.ch.push(
      SessionHistory(
        inReplyTo: 'sync1',
        sessionStartedAt: 0,
        events: const [
          UserInputEvt(ts: 1, id: 'u2', text: 'next'),
          AgentMessageEvt(ts: liveTs, inReplyTo: 'u2', text: 'narration text'),
        ],
        eos: true,
      ),
    );
    await _settle();

    final narration = messages(s.epk).where((r) => r.text == 'narration text');
    expect(
      narration.length,
      1,
      reason:
          'After the replay, the dropped turn renders exactly once '
          '(deterministic replay row). No random-uuid live row survives '
          'to dupe against it.',
    );
    s.conn.dispose();
    s.sync.dispose();
  });

  // Counter-test for the legacy-extension path: an extension that NEVER
  // sends agent_message(ts) must still get its streamed buffer committed at
  // AgentDone (the capability flag stays false → fallback is NOT
  // suppressed). Guards against the Layer 2 fix over-suppressing for legacy
  // peers.
  test('legacy extension (no agent_message(ts) ever): AgentDone still commits '
      'the streamed buffer', () async {
    final s = await setup();
    s.ch.push(UserInput(id: 'u1', text: 'go'));
    await _settle();
    // No agent_message(ts) ever arrives — legacy extension.
    s.ch.push(const AgentChunk(inReplyTo: 'u1', delta: 'hello world'));
    await _settle();
    s.ch.push(AgentDone(inReplyTo: 'u1'));
    await _settle();

    final narration = messages(s.epk).where((r) => r.text == 'hello world');
    expect(
      narration.length,
      1,
      reason:
          'A legacy extension that never sends agent_message(ts) must '
          'still commit the streamed buffer at AgentDone (random-uuid '
          'fallback). The Layer 2 suppression only applies once the '
          'capability is latched.',
    );
    s.conn.dispose();
    s.sync.dispose();
  });

  // Mixed-peer regression (review finding on Layer 2): the capability flag
  // is per-active-session, NOT process-global. A peer A that sent
  // agent_message(ts) (latching the flag) must NOT suppress the random-uuid
  // fallback for a later legacy peer B on a different session. activate()
  // resets the flag, so B's streamed buffer commits at AgentDone.
  test('capability flag is per-session: prior fixed peer does not suppress '
      'a later legacy peer\'s fallback', () async {
    final s = await setup();
    // Peer A: fixed extension — latches the capability flag.
    s.ch.push(UserInput(id: 'u1', text: 'go'));
    await _settle();
    const priorTs = 1000;
    s.ch.push(
      const AgentMessage(
        inReplyTo: 'u1',
        text: 'peer A deterministic text',
        ts: priorTs,
      ),
    );
    await _settle();
    s.ch.push(AgentDone(inReplyTo: 'u1'));
    await _settle();

    // Switch to peer B (a different session). adopt a channel for epkB so
    // conn.activePeer == epkB (frames are not origin-gated), push a PairOk
    // to bind epkB's session id, then activate() — which must reset the
    // capability flag.
    const epkB = 'epk_legacy_peer_zzz';
    _sessionByEpk[epkB] = 'session-legacy-peer';
    final chB = _FakeChannel();
    chB.defaultSessionId = 'session-legacy-peer';
    s.conn.adopt(
      chB,
      PeerRecord(
        remoteEpk: epkB,
        sessionName: 'Pi',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-01-01T00:00:00Z',
      ),
    );
    await _settle();
    chB.pushRaw(
      PairOk(
        inReplyTo: 'pairB',
        sessionName: 'Pi',
        sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
        roomId: 'main',
        sessionId: 'session-legacy-peer',
      ),
    );
    await _settle(); // ConnectionManager learns epkB's active session id
    await s.sync.activate(epkB, 'main');
    await _settle();

    // Peer B: legacy extension — only streams chunks, never agent_message(ts).
    chB.push(UserInput(id: 'u2', text: 'next'));
    await _settle();
    chB.push(const AgentChunk(inReplyTo: 'u2', delta: 'peer B streamed text'));
    await _settle();
    chB.push(AgentDone(inReplyTo: 'u2'));
    await _settle();

    final narration = messages(
      epkB,
    ).where((r) => r.text == 'peer B streamed text');
    expect(
      narration.length,
      1,
      reason:
          'After activate() to a new session, the capability flag must be '
          'reset so a legacy peer (no agent_message(ts)) still commits its '
          'streamed buffer at AgentDone. If the flag leaked from peer A, '
          'this text would be wrongly suppressed (lost).',
    );
    s.conn.dispose();
    s.sync.dispose();
  });

  // Regression for the multi-block collision the deep review caught.
  // A single SDK assistant message with MULTIPLE text blocks shares
  // (in_reply_to, ts) across blocks; the extension emits one agent_message
  // per block with a distinct message_id (sync_<ts>:assistant:<blockIndex>).
  // The app must use message_id as the stable key so blocks do NOT collide on
  // the same eventId (which would drop all but the first block, and then
  // AgentDone's skip would lose the rest). See
  // story-mobile-assistant-message-duplicated-live-replay decision 1.
  test(
    'multi-block assistant message: live agent_message per block does not collide',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'go'));
      await _settle();
      const liveTs = 3000;
      // Two text blocks in the same SDK assistant message (same ts).
      s.ch.push(
        const AgentMessage(
          inReplyTo: 'u1',
          text: 'first block',
          ts: liveTs,
          messageId: 'sync_3000:assistant:0',
        ),
      );
      s.ch.push(
        const AgentMessage(
          inReplyTo: 'u1',
          text: 'second block',
          ts: liveTs,
          messageId: 'sync_3000:assistant:1',
        ),
      );
      await _settle();

      final assistantRows = messages(
        s.epk,
      ).where((r) => r.role == MsgRole.assistant).toList();
      expect(
        assistantRows.length,
        2,
        reason:
            'Two text blocks with distinct message_ids must both survive '
            '(distinct eventIds). Previously both derived the same eventId '
            '(keyed only on inReplyTo+ts) so Hive deduped the second away '
            '→ message loss.',
      );
      expect(assistantRows.map((r) => r.text).toSet(), {
        'first block',
        'second block',
      });
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  // Regression for `story-mobile-assistant-message-duplicated-live-replay`
  // user-message follow-up (identity source (a), same class extended to user
  // messages). A live `user_input` echo carrying the SDK `ts` must commit with
  // the SAME deterministic eventId as the `UserInputEvt` replay path, so a live
  // commit + replay of the same user message collapse to ONE Hive row (deduped
  // by eventId) instead of two rows with incompatible schemes.
  test(
    'live user_input(ts) + replay UserInputEvt collapse to one row',
    () async {
      final s = await setup();
      // Live user_input echo carrying the SDK ts (the extension's
      // message_end-driven broadcast).
      const liveTs = 4000;
      s.ch.push(
        const UserInput(
          id: 'local_user1',
          text: 'hello from phone',
          ts: liveTs,
        ),
      );
      await _settle();
      final afterLive = messages(
        s.epk,
      ).where((r) => r.role == MsgRole.user).length;
      expect(afterLive, 1, reason: 'live user_input commits one row');

      // Replay the SAME user message via session_history. Under the old
      // scheme this would add a SECOND event-store row (incompatible
      // eventIds). With deterministic identity it collapses (and the
      // projection guard dedupes by id regardless).
      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync1',
          sessionStartedAt: 0,
          events: const [
            UserInputEvt(
              ts: liveTs,
              id: 'local_user1',
              text: 'hello from phone',
            ),
          ],
          eos: true,
        ),
      );
      await _settle();

      final userRows = messages(
        s.epk,
      ).where((r) => r.role == MsgRole.user).toList();
      expect(userRows.length, 1, reason: 'projection dedupes by id regardless');
      // The real convergence is in the event store: a live + replay for the
      // same (id, ts) must collapse to ONE UserMessageConfirmed event, not
      // two with incompatible eventIds. Pre-fix this was 2 (bloat); post-fix 1.
      final userConfirmedEvents =
          (await s.sync.debugTranscriptEventStore.readSession(
                transcriptKeyFor(s.epk),
              ))
              .whereType<UserMessageConfirmed>()
              .where((e) => e.clientMessageId == 'local_user1')
              .toList();
      expect(
        userConfirmedEvents.length,
        1,
        reason:
            'A live user_input(ts) and a replay UserInputEvt for the same '
            '(id, ts) must collapse to one event-store row (deduped by '
            'eventId). Previously the live path used a non-session-scoped '
            'eventId while replay used server:<sessionId>:user_input:'
            '<id>:<ts> — both survived as distinct Hive rows.',
      );
      expect(userRows.single.text, 'hello from phone');
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  // A preserving Pi restart rebuilds history from SDK messages after the
  // extension's in-memory delivered-user reservation is gone. The same user
  // message then keeps its SDK timestamp but falls back from the live app id to
  // `sync_<ts>`. Durable admission must use the restart-stable timestamp
  // identity, not the process-local reservation id.
  test(
    'cold Pi replay with rebuilt user id keeps the persisted prompt once',
    () async {
      final s = await setup();
      // The message_end-driven user_input for a workstation-typed message.
      // id is the turnId (local_-prefixed), ts is the SDK timestamp.
      const liveTs = 5000;
      s.ch.push(
        const UserInput(
          id: 'local_workstation_turn',
          text: 'restarted pi and loaded the apk',
          ts: liveTs,
        ),
      );
      await _settle();
      final afterLive = messages(
        s.epk,
      ).where((r) => r.role == MsgRole.user).length;
      expect(afterLive, 1, reason: 'single user_input commits one row');

      // After the extension process restarts, SDK backfill no longer has the
      // delivered-user reservation that carried the live app id.
      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync1',
          sessionStartedAt: 0,
          events: const [
            UserInputEvt(
              ts: liveTs,
              id: 'sync_5000',
              text: 'restarted pi and loaded the apk',
            ),
          ],
          eos: true,
        ),
      );
      await _settle();

      final userRows = messages(
        s.epk,
      ).where((record) => record.role == MsgRole.user).toList();
      final userConfirmedEvents =
          (await s.sync.debugTranscriptEventStore.readSession(
            transcriptKeyFor(s.epk),
          )).whereType<UserMessageConfirmed>().toList();
      expect(
        userConfirmedEvents,
        hasLength(1),
        reason: 'live and cold replay must share one durable event identity',
      );
      expect(userRows, hasLength(1));
      expect(userRows.single.id, 'local_workstation_turn');
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('re-applying an IDENTICAL SessionHistory is idempotent — no box churn, '
      'so the relay re-sending history on every reconnect no longer tears the '
      'list down and rebuilds it (plan/32 flicker fix)', () async {
    final s = await setup();
    final read = SessionReadRepository(LocalBoxes());
    var emits = 0;
    final sub = read.watchMessages(refFor(s.epk)).listen((_) => emits++);
    await _settle();

    SessionHistory hist(String inReplyTo) => SessionHistory(
      inReplyTo: inReplyTo,
      sessionStartedAt: 0,
      events: const [
        UserInputEvt(ts: 1, id: 'u1', text: 'hi'),
        AgentMessageEvt(ts: 2, inReplyTo: 'a1', text: 'hello'),
        ToolRequestEvt(ts: 3, toolCallId: 'c1', tool: 'Read', args: null),
      ],
      eos: true,
    );

    s.ch.push(hist('sync1'));
    await _settle();
    final afterFirst = emits;
    expect(afterFirst, greaterThan(1), reason: 'first apply populates rows');
    expect(messages(s.epk).map((r) => r.role), [
      MsgRole.user,
      MsgRole.assistant,
      MsgRole.tool,
    ]);

    // Relay re-delivers the SAME history (different in_reply_to, identical
    // events) — the reconcile must write nothing → no watch event → no emit.
    s.ch.push(hist('sync2'));
    await _settle();
    expect(
      emits,
      afterFirst,
      reason: 'identical re-apply must not emit (no list rebuild/flicker)',
    );

    await sub.cancel();
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'history replay preserves local pending events absent from replay',
    () async {
      final s = await setup();
      await s.sync.sendMessage('local draft');
      await _settle();
      final sentId = s.ch.sent.whereType<UserMessage>().last.id;
      expect(messages(s.epk).single.pending, isTrue);

      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync-preserve-pending',
          sessionStartedAt: 0,
          events: const [UserInputEvt(ts: 1, id: 'server-old', text: 'old')],
          eos: true,
        ),
      );
      await _settle();

      final rows = messages(s.epk);
      expect(rows.map((row) => row.text), <String>['old', 'local draft']);
      final pending = rows.singleWhere((row) => row.id == sentId);
      expect(pending.pending, isTrue);
      expect(pending.role, MsgRole.user);

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('history replay missing older local rows preserves them', () async {
    final s = await setup();
    s.ch.push(
      SessionHistory(
        inReplyTo: 'sync-full-prefix',
        sessionStartedAt: 0,
        events: const [
          UserInputEvt(ts: 1, id: 'older', text: 'older row'),
          AgentMessageEvt(ts: 2, inReplyTo: 'older', text: 'older answer'),
        ],
        eos: true,
      ),
    );
    await _settle();
    expect(messages(s.epk).map((row) => row.text), <String>[
      'older row',
      'older answer',
    ]);

    s.ch.push(
      SessionHistory(
        inReplyTo: 'sync-suffix-only',
        sessionStartedAt: 0,
        events: const [UserInputEvt(ts: 3, id: 'newer', text: 'newer row')],
        eos: true,
      ),
    );
    await _settle();

    expect(messages(s.epk).map((row) => row.text), <String>[
      'older row',
      'older answer',
      'newer row',
    ]);
    s.conn.dispose();
    s.sync.dispose();
  });

  test('duplicate replay rebuilds a missing disposable projection', () async {
    final s = await setup();
    SessionHistory history(String requestId) => SessionHistory(
      sessionId: s.sessionId,
      inReplyTo: requestId,
      sessionStartedAt: 1,
      events: const [UserInputEvt(ts: 1, id: 'u1', text: 'restored')],
      eos: true,
    );

    s.ch.pushRaw(history('initial-replay'));
    await _settle();
    expect(messages(s.epk).map((row) => row.text), ['restored']);

    await LocalBoxes().openMsgsBox(refFor(s.epk)).clear();
    expect(messages(s.epk), isEmpty, reason: 'projection is unbuilt');

    s.ch.pushRaw(history('churn-replay'));
    await _settle();

    expect(
      messages(s.epk).map((row) => row.text),
      ['restored'],
      reason: 'known durable events must rematerialize an empty projection',
    );
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'duplicate history replay through projection emits no Hive churn',
    () async {
      final s = await setup();
      final read = SessionReadRepository(LocalBoxes());
      var emits = 0;
      final sub = read.watchMessages(refFor(s.epk)).listen((_) => emits++);
      await _settle();

      final history = SessionHistory(
        inReplyTo: 'sync-duplicate-1',
        sessionStartedAt: 0,
        events: const [
          UserInputEvt(ts: 1, id: 'u1', text: 'hi'),
          AgentMessageEvt(ts: 2, inReplyTo: 'u1', text: 'done'),
        ],
        eos: true,
      );
      s.ch.push(history);
      await _settle();
      final afterFirst = emits;
      expect(afterFirst, greaterThan(1));

      final logLengthAfterFirst =
          (await s.sync.debugTranscriptEventStore.readSession(
            transcriptKeyFor(s.epk),
          )).length;

      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync-duplicate-2',
          sessionStartedAt: history.sessionStartedAt,
          events: history.events,
          eos: history.eos,
        ),
      );
      await _settle();

      final logLengthAfterDuplicate =
          (await s.sync.debugTranscriptEventStore.readSession(
            transcriptKeyFor(s.epk),
          )).length;
      expect(logLengthAfterDuplicate, logLengthAfterFirst);
      expect(emits, afterFirst);
      expect(messages(s.epk).map((row) => row.text), <String>['hi', 'done']);

      await sub.cancel();
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'reconnect-history fixture replays additively without replace semantics',
    () async {
      final s = await setup();
      final read = SessionReadRepository(LocalBoxes());
      var emits = 0;
      final sub = read.watchMessages(refFor(s.epk)).listen((_) => emits++);
      await _settle();

      await s.sync.sendMessage('still visible');
      await _settle();
      final localId = s.ch.sent.whereType<UserMessage>().last.id;
      expect(messages(s.epk).map((row) => row.text), <String>['still visible']);

      final replay = SessionHistory(
        sessionId: s.sessionId,
        inReplyTo: 'reconnect-history-is-replay-not-replace-1',
        sessionStartedAt: 10,
        events: const [
          UserInputEvt(ts: 10, id: 'srv_1', text: 'authoritative older row'),
        ],
        eos: true,
        truncated: true,
      );
      s.ch.pushRaw(replay);
      await _settle();

      expect(messages(s.epk).map((row) => row.text), <String>[
        'authoritative older row',
        'still visible',
      ]);
      expect(
        messages(s.epk).singleWhere((row) => row.id == localId).pending,
        isTrue,
      );
      final afterFirstLog = await s.sync.debugTranscriptEventStore.readSession(
        transcriptKeyFor(s.epk),
      );
      final afterFirstRows = [for (final row in messages(s.epk)) row.toJson()];
      final afterFirstEmits = emits;
      expect(afterFirstLog.map((event) => event.eventId).toSet(), hasLength(2));

      s.ch.pushRaw(
        SessionHistory(
          sessionId: s.sessionId,
          inReplyTo: 'reconnect-history-is-replay-not-replace-duplicate',
          sessionStartedAt: replay.sessionStartedAt,
          events: replay.events,
          eos: true,
          truncated: true,
        ),
      );
      await _settle();
      expect(
        await s.sync.debugTranscriptEventStore.readSession(
          transcriptKeyFor(s.epk),
        ),
        hasLength(afterFirstLog.length),
      );
      expect([for (final row in messages(s.epk)) row.toJson()], afterFirstRows);
      expect(emits, afterFirstEmits);

      s.ch.pushRaw(
        SessionHistory(
          sessionId: s.sessionId,
          inReplyTo: 'reconnect-history-is-replay-not-replace-empty',
          sessionStartedAt: replay.sessionStartedAt,
          events: const [],
          eos: true,
          truncated: true,
        ),
      );
      await _settle();
      expect(
        await s.sync.debugTranscriptEventStore.readSession(
          transcriptKeyFor(s.epk),
        ),
        hasLength(afterFirstLog.length),
      );
      expect([for (final row in messages(s.epk)) row.toJson()], afterFirstRows);
      expect(emits, afterFirstEmits);

      final workingBeforeForeign = s.sync.isWorking;
      final streamingBeforeForeign = s.sync.streaming;
      s.ch.pushRaw(
        SessionHistory(
          sessionId: 'foreign-session',
          inReplyTo: 'reconnect-history-is-replay-not-replace-foreign',
          sessionStartedAt: replay.sessionStartedAt + 1,
          events: const [
            UserInputEvt(ts: 11, id: 'foreign_1', text: 'must not appear'),
          ],
          eos: true,
        ),
      );
      await _settle();
      expect(
        await s.sync.debugTranscriptEventStore.readSession(
          transcriptKeyFor(s.epk),
        ),
        hasLength(afterFirstLog.length),
      );
      expect([for (final row in messages(s.epk)) row.toJson()], afterFirstRows);
      expect(s.sync.isWorking, workingBeforeForeign);
      expect(s.sync.streaming, streamingBeforeForeign);
      expect(
        messages(s.epk).map((row) => row.text),
        isNot(contains('must not appear')),
      );

      await sub.cancel();
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'msgs projection is disposable and rebuilds from transcript event store',
    () async {
      final s = await setup();
      s.ch.push(
        SessionHistory(
          sessionId: s.sessionId,
          inReplyTo: 'sync-rebuild-source',
          sessionStartedAt: 0,
          events: const [
            UserInputEvt(ts: 1, id: 'u1', text: 'hi'),
            AgentMessageEvt(ts: 2, inReplyTo: 'u1', text: 'done'),
            CompactionEvt(ts: 3, summary: 'compacted', tokensBefore: 5000),
          ],
          eos: true,
        ),
      );
      await _settle();
      final expected = [
        for (final row in messages(s.epk))
          (role: row.role, id: row.id, text: row.text, status: row.status),
      ];
      expect(expected.map((row) => row.text), <String>[
        'hi',
        'done',
        'compacted',
      ]);
      expect(
        await s.sync.debugTranscriptEventStore.readSession(
          transcriptKeyFor(s.epk),
        ),
        hasLength(3),
      );

      await LocalBoxes().openMsgsBox(refFor(s.epk)).clear();
      expect(messages(s.epk), isEmpty, reason: 'msgs box is disposable');

      s.sync.dispose();
      final sync2 = SyncService(s.conn, LocalBoxes());
      await sync2.activate(s.epk, 'main');
      await _settle();

      final rebuilt = [
        for (final row in messages(s.epk))
          (role: row.role, id: row.id, text: row.text, status: row.status),
      ];
      expect(rebuilt, expected);

      s.conn.dispose();
      sync2.dispose();
    },
  );

  test(
    'late authoritative echo after timeout confirms and removes failure',
    () async {
      final s = await setup(
        pendingSendTimeout: const Duration(milliseconds: 20),
      );
      await s.sync.sendMessage('eventual echo');
      await _settle();
      final sentId = s.ch.sent.whereType<UserMessage>().last.id;

      await _waitUntil(
        () => messages(s.epk).singleOrNull?.status == UserMsgStatus.failed,
        reason: 'the pending send timeout projection',
      );
      final failed = messages(s.epk).single;
      expect(failed.id, sentId);
      expect(failed.role, MsgRole.user);
      expect(failed.status, UserMsgStatus.failed);
      expect(failed.text, 'eventual echo');

      s.ch.push(UserInput(id: sentId, text: 'eventual echo'));
      await _waitUntil(
        () => messages(s.epk).singleOrNull?.status == UserMsgStatus.confirmed,
        reason: 'the late authoritative echo projection',
      );

      final rows = messages(s.epk);
      expect(rows, hasLength(1));
      expect(rows.single.id, sentId);
      expect(rows.single.role, MsgRole.user);
      expect(rows.single.text, 'eventual echo');
      expect(rows.single.pending, isFalse);

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'late authoritative history replay after timeout confirms and removes failure',
    () async {
      final s = await setup(
        pendingSendTimeout: const Duration(milliseconds: 20),
      );
      await s.sync.sendMessage('eventual replay');
      await _settle();
      final sentId = s.ch.sent.whereType<UserMessage>().last.id;

      await _waitUntil(
        () => messages(s.epk).singleOrNull?.status == UserMsgStatus.failed,
        reason: 'the replay test pending-send timeout projection',
      );
      expect(messages(s.epk).single.status, UserMsgStatus.failed);

      s.ch.push(
        SessionHistory(
          sessionId: s.sessionId,
          inReplyTo: 'sync-late-confirmation',
          sessionStartedAt: 1000,
          events: [UserInputEvt(ts: 1, id: sentId, text: 'eventual replay')],
          eos: true,
        ),
      );
      await _waitUntil(
        () => messages(s.epk).singleOrNull?.status == UserMsgStatus.confirmed,
        reason: 'the late authoritative replay projection',
      );

      final rows = messages(s.epk);
      expect(rows, hasLength(1));
      expect(rows.single.id, sentId);
      expect(rows.single.role, MsgRole.user);
      expect(rows.single.text, 'eventual replay');
      expect(rows.single.status, UserMsgStatus.confirmed);
      expect(
        await s.sync.debugTranscriptEventStore.readSession(
          transcriptKeyFor(s.epk),
        ),
        hasLength(3),
        reason:
            'the submitted, failed, and confirmed events all remain in the log',
      );

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'transcript log drives replay and converges idle across terminal outcomes',
    () async {
      final s = await setup();

      s.ch.push(UserInput(id: 'success-u1', text: 'succeed'));
      await _settle();
      s.ch.push(AgentChunk(inReplyTo: 'success-u1', delta: 'done'));
      await _settle();
      s.ch.push(AgentDone(inReplyTo: 'success-u1'));
      await _settle();
      expect(s.sync.isWorking, isFalse, reason: 'success converges idle');

      s.ch.push(UserInput(id: 'error-u1', text: 'fail'));
      await _settle();
      s.ch.push(AgentChunk(inReplyTo: 'error-u1', delta: 'partial'));
      s.ch.push(
        ErrorMessage(
          sessionId: s.sessionId,
          inReplyTo: 'error-u1',
          code: 'provider_error',
          message: 'boom',
        ),
      );
      await _settle();
      expect(s.sync.isWorking, isFalse, reason: 'error converges idle');

      s.ch.push(UserInput(id: 'cancel-u1', text: 'cancel'));
      await _settle();
      s.ch.push(AgentChunk(inReplyTo: 'cancel-u1', delta: 'partial'));
      s.ch.push(Cancelled(inReplyTo: 'cancel-req', targetId: 'cancel-u1'));
      await _settle();
      expect(s.sync.isWorking, isFalse, reason: 'cancel converges idle');

      s.ch.push(
        Compaction(
          sessionId: s.sessionId,
          summary: 'compacted fixture',
          tokensBefore: 1234,
          ts: 1700000001234,
        ),
      );
      await _settle();
      expect(s.sync.isWorking, isFalse, reason: 'compaction converges idle');

      final log = await s.sync.debugTranscriptEventStore.readSession(
        transcriptKeyFor(s.epk),
      );
      expect(
        log.whereType<UserMessageConfirmed>().map(
          (event) => event.clientMessageId,
        ),
        containsAll(<String>['success-u1', 'error-u1', 'cancel-u1']),
      );
      expect(log.whereType<AssistantDoneReceived>(), isNotEmpty);
      expect(
        log.whereType<CompactionRecorded>().single.summary,
        'compacted fixture',
      );

      await LocalBoxes().openMsgsBox(refFor(s.epk)).clear();
      s.sync.dispose();
      final sync2 = SyncService(s.conn, LocalBoxes());
      await sync2.activate(s.epk, 'main');
      await _settle();

      final replayedTexts = messages(s.epk).map((row) => row.text).toList();
      expect(
        replayedTexts,
        containsAll(<String>[
          'succeed',
          'done',
          'fail',
          'cancel',
          'compacted fixture',
        ]),
      );
      expect(replayedTexts, contains(startsWith('⚠ provider_error:')));
      expect(sync2.isWorking, isFalse, reason: 'replay rebuild stays idle');

      s.conn.dispose();
      sync2.dispose();
    },
  );

  test(
    'detached transcript failure degrades once, requests replay, recovers, and preserves turn convergence',
    () async {
      final store = _MemoryTranscriptStore();
      final debug = _RecordingDebugLog();
      final s = await setup(transcriptEventStore: store, debugLog: debug);
      final sessionEvents = <SessionEvent>[];
      final sub = s.sync.events.listen(sessionEvents.add);
      s.ch.sent.clear();

      s.ch.push(UserInput(id: 'failure-u1', text: 'keep working'));
      await _settle();
      expect(s.sync.isWorking, isTrue);

      store.failNextAppend = true;
      s.ch.push(AgentChunk(inReplyTo: 'failure-u1', delta: 'partial'));
      await _settle();
      expect(
        s.sync.isWorking,
        isTrue,
        reason: 'a non-terminal persistence failure must not idle the turn',
      );
      expect(
        sessionEvents.whereType<SessionPersistenceDegraded>(),
        hasLength(1),
      );
      expect(s.ch.sent.whereType<SessionSync>(), hasLength(1));
      expect(
        debug.events.whereType<LifecycleFailureEvent>().where(
          (event) => event.operation == LifecycleOperation.transcriptWrite,
        ),
        hasLength(1),
      );

      store.failNextAppend = true;
      s.ch.push(
        ToolResult(toolCallId: 'tool-failure', result: const {'ok': true}),
      );
      await _settle();
      expect(
        sessionEvents.whereType<SessionPersistenceDegraded>(),
        hasLength(1),
        reason: 'the visible warning is latched rather than repeated',
      );

      s.ch.push(
        AgentMessage(
          inReplyTo: 'failure-u1',
          text: 'recovered write',
          ts: 1700000001000,
        ),
      );
      await _settle();
      expect(
        sessionEvents.whereType<SessionPersistenceRecovered>(),
        hasLength(1),
      );

      store.failNextAppend = true;
      s.ch.push(AgentDone(inReplyTo: 'failure-u1'));
      await _settle();
      expect(
        s.sync.isWorking,
        isFalse,
        reason: 'terminal state settles idle even when its append fails',
      );
      expect(
        store
            .eventsFor(transcriptKeyFor(s.epk))
            .whereType<AssistantDoneReceived>(),
        isEmpty,
        reason: 'a failed append does not invent a transcript row',
      );

      await sub.cancel();
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('a fail-once transcript read recovers on the next replay', () async {
    final store = _MemoryTranscriptStore();
    final s = await setup(transcriptEventStore: store);
    final sessionEvents = <SessionEvent>[];
    final sub = s.sync.events.listen(sessionEvents.add);
    final history = SessionHistory(
      sessionId: s.sessionId,
      inReplyTo: 'read-recovery',
      sessionStartedAt: 1000,
      events: const [UserInputEvt(ts: 1, id: 'read-u1', text: 'history')],
      eos: true,
    );

    s.ch.push(history);
    await _settle();
    expect(store.eventsFor(transcriptKeyFor(s.epk)), isNotEmpty);

    store.failNextRead = true;
    s.ch.push(history);
    await _settle();
    expect(sessionEvents.whereType<SessionPersistenceDegraded>(), hasLength(1));

    s.ch.push(history);
    await _settle();
    expect(
      sessionEvents.whereType<SessionPersistenceRecovered>(),
      hasLength(1),
    );
    expect(store.eventsFor(transcriptKeyFor(s.epk)), isNotEmpty);

    await sub.cancel();
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'stale append completion cannot diagnose or publish after rotation',
    () async {
      final store = _MemoryTranscriptStore();
      final debug = _RecordingDebugLog();
      final s = await setup(transcriptEventStore: store, debugLog: debug);
      final sessionEvents = <SessionEvent>[];
      final sub = s.sync.events.listen(sessionEvents.add);
      final gate = Completer<void>();
      store
        ..appendGate = gate
        ..failNextAppend = true;

      s.ch.push(AgentChunk(inReplyTo: 'old-turn', delta: 'stale'));
      await Future<void>.delayed(Duration.zero);
      const rotated = 'stale-completion-rotated';
      _sessionByEpk[s.epk] = rotated;
      s.ch.defaultSessionId = rotated;
      s.ch.pushRaw(
        PairOk(
          inReplyTo: 'rotate-stale-completion',
          sessionName: 'Pi',
          sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
          roomId: 'main',
          sessionId: rotated,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 70));
      gate.complete();
      await _settle();
      await _settle();

      expect(sessionEvents.whereType<SessionPersistenceDegraded>(), isEmpty);
      expect(
        debug.events.whereType<LifecycleFailureEvent>().where(
          (event) => event.operation == LifecycleOperation.transcriptWrite,
        ),
        isEmpty,
        reason: 'the old session completion cannot publish diagnostics',
      );
      expect(s.sync.activeSessionRef?.sessionId, rotated);

      await sub.cancel();
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'reconnect generation change cannot swallow a queued submission',
    () async {
      final store = _MemoryTranscriptStore();
      final s = await setup(transcriptEventStore: store);
      addTearDown(() {
        s.sync.dispose();
        s.conn.dispose();
      });

      final appendGate = Completer<void>();
      final appendStarted = Completer<void>();
      store
        ..appendGate = appendGate
        ..appendStarted = appendStarted;

      final occupyingSend = s.sync.sendMessage('occupy transcript write');
      await appendStarted.future.timeout(const Duration(seconds: 1));
      final racedSend = s.sync.sendMessage('survive reconnect generation');

      final retrying = s.conn.statusStream.firstWhere(
        (status) => status is StatusRetrying,
      );
      await s.ch.loseConnection();
      await retrying.timeout(const Duration(seconds: 1));
      appendGate.complete();
      await Future.wait(<Future<void>>[occupyingSend, racedSend]);

      await _waitUntil(
        () =>
            messages(
              s.epk,
            ).any((row) => row.text == 'survive reconnect generation') ||
            s.sync.identityPendingMessages.any(
              (row) =>
                  row is UserMsg && row.text == 'survive reconnect generation',
            ),
        reason: 'the reconnect-raced submission to remain visible',
      );

      final reconnect = _FakeChannel()..defaultSessionId = s.sessionId;
      s.conn.adopt(
        reconnect,
        PeerRecord(
          remoteEpk: s.epk,
          sessionName: 'Pi',
          relayUrl: 'ws://localhost',
          pairedAt: '2026-01-01T00:00:00Z',
          roomId: 'main',
        ),
      );
      reconnect.pushControl(
        RoomsSnapshot(
          peer: s.epk,
          rooms: [
            RoomInfo(roomId: 'main', sessionId: s.sessionId, startedAt: 2),
          ],
        ),
      );

      await _waitUntil(
        () => reconnect.sent.whereType<UserMessage>().any(
          (message) => message.text == 'survive reconnect generation',
        ),
        reason: 'the reconnect-raced submission to be re-sent',
      );
      expect(
        messages(
          s.epk,
        ).where((row) => row.text == 'survive reconnect generation'),
        hasLength(1),
      );
    },
  );

  test(
    'sendMessage append completion cannot mutate or send after channel replacement',
    () async {
      final store = _MemoryTranscriptStore();
      final s = await setup(transcriptEventStore: store);
      final appendGate = Completer<void>();
      final appendStarted = Completer<void>();
      store
        ..appendGate = appendGate
        ..appendStarted = appendStarted;

      final sending = s.sync.sendMessage('belongs to the old channel');
      await appendStarted.future.timeout(const Duration(seconds: 1));

      final replacement = _FakeChannel()..defaultSessionId = 'replacement';
      s.conn.adopt(
        replacement,
        const PeerRecord(
          remoteEpk: 'replacement-peer',
          sessionName: 'Replacement',
          relayUrl: 'ws://localhost',
          pairedAt: '2026-01-01T00:00:00Z',
        ),
      );
      appendGate.complete();
      await sending;

      expect(s.ch.sent.whereType<UserMessage>(), isEmpty);
      expect(replacement.sent.whereType<UserMessage>(), isEmpty);
      expect(s.sync.debugPendingSendTimerCount, 0);
      expect(s.sync.turnProjection.working, isFalse);

      s.sync.dispose();
      s.conn.dispose();
    },
  );

  test(
    'sendMessage append completion cannot mutate or send after disposal',
    () async {
      final store = _MemoryTranscriptStore();
      final s = await setup(transcriptEventStore: store);
      final appendGate = Completer<void>();
      final appendStarted = Completer<void>();
      store
        ..appendGate = appendGate
        ..appendStarted = appendStarted;

      final sending = s.sync.sendMessage('disposed before persistence returns');
      await appendStarted.future.timeout(const Duration(seconds: 1));
      s.sync.dispose();
      appendGate.complete();
      await sending;

      expect(s.ch.sent.whereType<UserMessage>(), isEmpty);
      expect(s.sync.debugPendingSendTimerCount, 0);
      expect(s.sync.turnProjection.working, isFalse);

      s.conn.dispose();
    },
  );

  test(
    'terminal epoch keeps idle when an older chunk completes before a failed terminal append',
    () async {
      final store = _MemoryTranscriptStore();
      final s = await setup(transcriptEventStore: store);
      final sessionEvents = <SessionEvent>[];
      final sub = s.sync.events.listen(sessionEvents.add);
      final appendGate = Completer<void>();
      final appendStarted = Completer<void>();
      store
        ..appendGate = appendGate
        ..appendStarted = appendStarted;

      s.ch.push(AgentChunk(inReplyTo: 'epoch-turn', delta: 'stale partial'));
      await appendStarted.future.timeout(const Duration(seconds: 1));
      expect(s.sync.turnProjection.working, isTrue);

      store.failAppendCall = 2;
      s.ch.push(AgentDone(inReplyTo: 'epoch-turn'));
      await _waitUntil(
        () => !s.sync.turnProjection.working,
        reason: 'the synchronous terminal idle transition',
      );

      appendGate.complete();
      await _waitUntil(
        () => store.appendCalls >= 2,
        reason: 'the queued terminal append attempt',
      );
      await _waitUntil(
        () => sessionEvents.whereType<SessionPersistenceDegraded>().isNotEmpty,
        reason: 'the failed terminal append diagnostic',
      );

      expect(s.sync.turnProjection.working, isFalse);
      expect(s.sync.streaming, isNull);

      await sub.cancel();
      s.sync.dispose();
      s.conn.dispose();
    },
  );

  test('stale held-message read cannot send after session rotation', () async {
    final store = _MemoryTranscriptStore();
    final s = await setup(transcriptEventStore: store);
    s.ch.pushControl(RoomEnded(peer: s.epk, roomId: 'main', sinceTs: 1));
    await _settle();
    await s.sync.sendMessage('held for stale read');
    await _settle();
    final held = store
        .eventsFor(transcriptKeyFor(s.epk))
        .whereType<UserMessageSubmitted>()
        .single;
    expect(held.held, isTrue);
    s.ch.sent.clear();

    final readGate = Completer<void>();
    final readStarted = Completer<void>();
    store
      ..readGate = readGate
      ..readStarted = readStarted;
    s.ch.pushControl(
      RoomAnnounced(
        peer: s.epk,
        roomId: 'main',
        sessionId: s.sessionId,
        startedAt: 2,
      ),
    );
    await readStarted.future.timeout(const Duration(seconds: 1));

    const rotated = 'held-read-rotated';
    _sessionByEpk[s.epk] = rotated;
    s.ch.defaultSessionId = rotated;
    s.ch.pushRaw(
      PairOk(
        inReplyTo: 'rotate-held-read',
        sessionName: 'Pi',
        sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
        roomId: 'main',
        sessionId: rotated,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    readGate.complete();
    await _settle();
    await _settle();
    await _settle();

    expect(
      s.ch.sent.whereType<UserMessage>().where(
        (message) => message.id == held.clientMessageId,
      ),
      isEmpty,
      reason: 'the old-session held message must not send after rotation',
    );
    expect(s.sync.activeSessionRef?.sessionId, rotated);
    final syncs = s.ch.sent.whereType<SessionSync>().toList();
    expect(syncs, isNotEmpty);
    expect(
      syncs,
      everyElement(
        predicate<SessionSync>((message) => message.sessionId == rotated),
      ),
    );

    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'room metadata skips transcript reads while fresh-live replays once',
    () async {
      final store = _MemoryTranscriptStore();
      final s = await setup(transcriptEventStore: store);
      final initialReads = store.readCalls;

      for (var i = 0; i < 6; i++) {
        s.ch.pushControl(
          RoomMetaUpdated(
            peer: s.epk,
            roomId: 'main',
            working: i.isEven,
            hasModel: false,
            hasThinking: false,
            hasSessionId: false,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
      expect(store.readCalls, initialReads);

      s.ch.pushControl(RoomEnded(peer: s.epk, roomId: 'main', sinceTs: 1));
      await _waitUntil(
        () => !s.conn.isRoomLive(s.epk, 'main'),
        reason: 'active room to become stale',
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(store.readCalls, initialReads);

      final replayStarted = Completer<void>();
      store.readStarted = replayStarted;
      store.readGate = Completer<void>()..complete();
      s.ch.pushControl(
        RoomAnnounced(
          peer: s.epk,
          roomId: 'main',
          sessionId: s.sessionId,
          startedAt: 2,
          working: false,
        ),
      );
      await replayStarted.future.timeout(const Duration(seconds: 1));
      await _waitUntil(
        () => store.readCalls == initialReads + 1,
        reason: 'one fresh-live held replay read',
      );
      expect(store.readCalls, initialReads + 1);

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'runtime put is awaited in the queue and diagnosed on failure',
    () async {
      Completer<void>? putGate;
      Completer<void>? putStarted;
      var failNextPut = false;
      final debug = _RecordingDebugLog();
      final s = await setup(
        debugLog: debug,
        runtimeRecordWriter: (key, value) async {
          final started = putStarted;
          if (started != null && !started.isCompleted) started.complete();
          final gate = putGate;
          if (gate != null) await gate.future;
          if (failNextPut) {
            failNextPut = false;
            throw StateError('runtime put failed');
          }
        },
      );

      putGate = Completer<void>();
      putStarted = Completer<void>();
      s.ch.pushControl(RoomEnded(peer: s.epk, roomId: 'main', sinceTs: 1));
      await putStarted.future.timeout(const Duration(seconds: 1));

      var sendCompleted = false;
      final send = s.sync
          .sendMessage('queued behind runtime put')
          .then((_) => sendCompleted = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sendCompleted, isFalse);
      putGate.complete();
      putGate = null;
      await send;
      expect(sendCompleted, isTrue);

      failNextPut = true;
      s.ch.pushControl(
        RoomAnnounced(
          peer: s.epk,
          roomId: 'main',
          sessionId: s.sessionId,
          startedAt: 2,
          working: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        debug.events.whereType<LifecycleFailureEvent>().where(
          (event) => event.operation == LifecycleOperation.runtimeWrite,
        ),
        isNotEmpty,
      );

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'session replacement partitions transcript logs and starts a fresh projection',
    () async {
      final s = await setup();
      final oldSession = s.sessionId;
      s.ch.push(UserInput(id: 'old-u1', text: 'old session'));
      s.ch.push(AgentMessage(inReplyTo: 'old-u1', text: 'old reply'));
      await _settle();
      expect(messages(s.epk, oldSession).map((row) => row.text), <String>[
        'old session',
        'old reply',
      ]);
      expect(
        await s.sync.debugTranscriptEventStore.readSession(
          transcriptKeyFor(s.epk, oldSession),
        ),
        hasLength(2),
      );

      const newSession = 'session-replacement-fixture';
      _sessionByEpk[s.epk] = newSession;
      s.ch.defaultSessionId = newSession;
      s.ch.pushRaw(
        PairOk(
          inReplyTo: 'pair-new-session',
          sessionName: 'Pi',
          sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
          roomId: 'main',
          sessionId: newSession,
        ),
      );
      await _settle();
      await _settle();

      expect(messages(s.epk, newSession), isEmpty);
      expect(
        await s.sync.debugTranscriptEventStore.readSession(
          transcriptKeyFor(s.epk, newSession),
        ),
        isEmpty,
      );
      expect(messages(s.epk, oldSession).map((row) => row.text), <String>[
        'old session',
        'old reply',
      ]);

      s.ch.push(UserInput(id: 'new-u1', text: 'new session'));
      await _settle();
      expect(messages(s.epk, newSession).map((row) => row.text), <String>[
        'new session',
      ]);
      expect(
        await s.sync.debugTranscriptEventStore.readSession(
          transcriptKeyFor(s.epk, oldSession),
        ),
        hasLength(2),
        reason: 'session replacement must not clear the prior canonical log',
      );

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'switching the writer to a new session: a late frame from the OLD '
    "connection is dropped — it neither writes the new box nor appears in the "
    "new session's read projection (plan/32f session-switch bleed)",
    () async {
      final s = await setup(); // bound to s.epk (peer A)
      s.ch.push(UserInput(id: 'a1', text: 'from chat1'));
      await _settle();
      expect(messages(s.epk), hasLength(1));

      // Switch the writer to chat 2 (epkB) WITHOUT a new channel — simulates
      // the window where the chat calls activate(epkB) before switchTo tears
      // the old peer's channel down. _activeEpk moves; the old channel (origin
      // = peer A) is still draining.
      const epkB = 'epk_chat2_zzz';
      _sessionByEpk[epkB] = 'session-chat2';
      final read = SessionReadRepository(LocalBoxes());
      final seenLens = <int>[];
      final sub = read
          .watchMessages(refFor(epkB))
          .listen((rows) => seenLens.add(rows.length));
      await s.sync.activate(epkB, 'main');
      await _settle();

      // Straggler frame on the OLD (peer A) channel.
      s.ch.push(UserInput(id: 'late', text: 'late chat1'));
      await _settle();

      expect(
        messages(epkB),
        isEmpty,
        reason: 'old-connection frame must not bleed into the new box',
      );
      expect(
        seenLens.every((n) => n == 0),
        isTrue,
        reason: "chat 2's projection never shows chat 1 rows",
      );
      expect(
        messages(s.epk),
        hasLength(1),
        reason: 'chat 1 box keeps exactly its own row (late frame dropped)',
      );

      await sub.cancel();
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('compaction ServerMessage writes a system row that projects to a '
      'CompactionMsg system bubble (plan/32)', () async {
    final s = await setup();
    s.ch.push(
      Compaction(
        summary: 'recapped the thread',
        tokensBefore: 12000,
        ts: 1700000000000,
      ),
    );
    await _settle();

    final m = messages(s.epk);
    expect(m, hasLength(1));
    expect(m.first.role, MsgRole.compaction);
    expect(m.first.text, 'recapped the thread');
    expect(m.first.tokensBefore, 12000);
    // Projects to the domain system-bubble message.
    expect(m.first.toChatMessage(), isA<CompactionMsg>());

    s.conn.dispose();
    s.sync.dispose();
  });

  test('compaction event in session_history reconstructs the system row on '
      're-sync (plan/32)', () async {
    final s = await setup();
    s.ch.push(
      SessionHistory(
        inReplyTo: 'sync1',
        sessionStartedAt: 0,
        events: const [
          UserInputEvt(ts: 1, id: 'u1', text: 'hi'),
          AgentMessageEvt(ts: 2, inReplyTo: 'a1', text: 'hello'),
          CompactionEvt(ts: 3, summary: 'compacted', tokensBefore: 5000),
        ],
        eos: true,
      ),
    );
    await _settle();

    final m = messages(s.epk);
    expect(m.map((r) => r.role), [
      MsgRole.user,
      MsgRole.assistant,
      MsgRole.compaction,
    ]);
    expect(m.last.text, 'compacted');
    expect(m.last.tokensBefore, 5000);
    expect(m.last.toChatMessage(), isA<CompactionMsg>());

    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'clearActiveSession wipes the rows while preserving session index metadata',
    () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u1', text: 'hi'));
      await _settle();
      expect(messages(s.epk), hasLength(1));

      await s.sync.clearActiveSession();
      await _settle();
      expect(messages(s.epk), isEmpty);
      expect(index(s.epk), isNotNull);
      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'clearActiveSession clears projection buffer before later replay',
    () async {
      final s = await setup();
      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync-base-buffer',
          sessionStartedAt: 1000,
          events: const [UserInputEvt(ts: 1, id: 'base', text: 'base row')],
          eos: true,
        ),
      );
      await _waitUntil(
        () => messages(s.epk).map((row) => row.id).contains('base'),
        reason: 'the base history projection',
      );
      expect(messages(s.epk).map((r) => r.id), ['base']);

      await s.sync.clearActiveSession();
      await _settle();
      expect(messages(s.epk), isEmpty);

      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync-replay-after-clear',
          sessionStartedAt: 1000,
          events: const [UserInputEvt(ts: 2, id: 'fresh', text: 'fresh row')],
          eos: true,
        ),
      );
      await _waitUntil(
        () => messages(s.epk).map((row) => row.id).contains('fresh'),
        reason: 'the post-clear history projection',
      );

      expect(
        messages(s.epk).map((r) => r.id),
        ['fresh'],
        reason: 'pre-clear event-log rows must not be resurrected',
      );

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test('clearActiveSession resets the in-memory turn state — working/streaming '
      'converge false on a mid-turn session wipe (plan/32)', () async {
    final s = await setup();

    // Mid-turn: working flag up, streaming buffer populated, reply target set.
    s.ch.push(AgentChunk(inReplyTo: 'r1', delta: 'thinking...'));
    await _settle();
    expect(s.sync.isWorking, isTrue);
    expect(s.sync.streaming, isNotNull);
    expect(s.sync.workingReplyTo, 'r1');

    final flags = <bool>[];
    final sub = s.sync.workingStream.listen(flags.add);

    // `session_new` wipe boundary: clear must converge working state false,
    // not leave a stale cancel target / streaming cursor.
    await s.sync.clearActiveSession();
    await _settle();

    expect(
      s.sync.isWorking,
      isFalse,
      reason: 'session clear must idle the in-memory working flag',
    );
    expect(
      s.sync.streaming,
      isNull,
      reason: 'session clear must drop the streaming cursor',
    );
    expect(
      s.sync.workingReplyTo,
      isNull,
      reason: 'session clear must clear the stale cancel target',
    );
    expect(
      flags,
      contains(false),
      reason: 'listeners are notified the flag cleared',
    );
    expect(messages(s.epk), isEmpty);

    await sub.cancel();
    s.conn.dispose();
    s.sync.dispose();
  });

  test(
    'clearActiveSession with no-index session accepts replay after clear',
    () async {
      final s = await setup();
      expect(messages(s.epk), isEmpty);
      expect(index(s.epk), isNull);

      await s.sync.clearActiveSession();
      await _settle();
      expect(messages(s.epk), isEmpty);
      expect(index(s.epk), isNull);

      // (a) first replay after clear establishes the starting boundary.
      final staleStartedAt = DateTime.now().millisecondsSinceEpoch - 120_000;
      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync-stale-empty',
          sessionStartedAt: staleStartedAt,
          events: const [
            UserInputEvt(ts: 1, id: 'stale', text: 'from active session'),
          ],
          eos: true,
        ),
      );
      await _settle();
      expect(messages(s.epk).map((r) => r.id), ['stale']);
      expect(
        index(s.epk)?.sessionStartedAt,
        DateTime.fromMillisecondsSinceEpoch(staleStartedAt),
      );

      // (b) a replacement clear is still supported before the next boundary replay
      // arrives.
      await s.sync.clearActiveSession();
      await _settle();
      expect(messages(s.epk), isEmpty);

      // (c) fresh current replay below the phone's wall clock is accepted.
      final currentSessionStartedAt =
          DateTime.now().millisecondsSinceEpoch - 90_000;
      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync-current',
          sessionStartedAt: currentSessionStartedAt,
          events: const [
            UserInputEvt(ts: 2, id: 'fresh', text: 'from active session'),
          ],
          eos: true,
        ),
      );
      await _settle();
      expect(messages(s.epk).map((r) => r.id), ['fresh']);
      expect(
        index(s.epk)?.sessionStartedAt,
        DateTime.fromMillisecondsSinceEpoch(currentSessionStartedAt),
      );

      // (d) older than the accepted current session is dropped.
      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync-older',
          sessionStartedAt: currentSessionStartedAt - 10,
          events: const [
            UserInputEvt(
              ts: 3,
              id: 'older-after-current',
              text: 'older than current',
            ),
          ],
          eos: true,
        ),
      );
      await _settle();
      expect(messages(s.epk).map((r) => r.id), ['fresh']);

      // (e) same boundary replay is accepted to keep reconnect replay semantics,
      // but replay is additive: omitted rows are not deleted just because a
      // same-session payload does not include them.
      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync-current-equal',
          sessionStartedAt: currentSessionStartedAt,
          events: const [
            UserInputEvt(ts: 4, id: 'equal', text: 'reconnect same boundary'),
          ],
          eos: true,
        ),
      );
      await _settle();
      expect(messages(s.epk).map((r) => r.id), ['fresh', 'equal']);

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'clearActiveSession preserves sessionStartedAt high-water and drops stale replay',
    () async {
      final s = await setup();

      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync-base',
          sessionStartedAt: 1000,
          events: const [UserInputEvt(ts: 1, id: 'base', text: 'legacy row')],
          eos: true,
        ),
      );
      await _settle();
      expect(messages(s.epk), hasLength(1));
      expect(
        index(s.epk)?.sessionStartedAt,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );

      await s.sync.clearActiveSession();
      await _settle();
      expect(messages(s.epk), isEmpty);
      expect(
        index(s.epk)?.sessionStartedAt,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );

      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync-stale',
          sessionStartedAt: 999,
          events: const [
            UserInputEvt(ts: 2, id: 'stale', text: 'from old session'),
          ],
          eos: true,
        ),
      );
      await _settle();
      expect(messages(s.epk), isEmpty);

      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync-fresh',
          sessionStartedAt: 1001,
          events: const [UserInputEvt(ts: 3, id: 'fresh', text: 'fresh row')],
          eos: true,
        ),
      );
      await _settle();
      final rows = messages(s.epk);
      expect(rows.map((r) => r.id), ['fresh']);
      expect(
        index(s.epk)?.sessionStartedAt,
        DateTime.fromMillisecondsSinceEpoch(1001),
      );

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'stale replay is rejected inside the serialized append boundary',
    () async {
      final s = await setup();

      final newer = s.sync.debugApplyHistory(
        SessionHistory(
          sessionId: s.sessionId,
          inReplyTo: 'sync-newer-racing',
          sessionStartedAt: 1000,
          events: const [UserInputEvt(ts: 1, id: 'newer', text: 'newer row')],
          eos: true,
        ),
      );
      final older = s.sync.debugApplyHistory(
        SessionHistory(
          sessionId: s.sessionId,
          inReplyTo: 'sync-older-racing',
          sessionStartedAt: 999,
          events: const [UserInputEvt(ts: 2, id: 'older', text: 'older row')],
          eos: true,
        ),
      );
      await Future.wait([newer, older]);
      await _settle();

      expect(messages(s.epk).map((r) => r.id), ['newer']);
      expect(
        await s.sync.debugTranscriptEventStore.readSession(
          transcriptKeyFor(s.epk),
        ),
        hasLength(1),
        reason: 'the stale batch must not be appended to the source log',
      );
      expect(
        index(s.epk)?.sessionStartedAt,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  test(
    'accepts replay above high-water even when below the phone clock',
    () async {
      final s = await setup();
      const baselineStartedAt = 1_700_000_000;
      const skewedStartedAt = 1_700_000_100;
      final phoneNow = DateTime.now().millisecondsSinceEpoch;
      expect(phoneNow, greaterThan(skewedStartedAt));

      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync-baseline',
          sessionStartedAt: baselineStartedAt,
          events: const [
            UserInputEvt(ts: 1, id: 'baseline', text: 'baseline row'),
          ],
          eos: true,
        ),
      );
      await _settle();
      expect(
        index(s.epk)?.sessionStartedAt,
        DateTime.fromMillisecondsSinceEpoch(baselineStartedAt),
      );

      await s.sync.clearActiveSession();
      await _settle();
      expect(
        index(s.epk)?.sessionStartedAt,
        DateTime.fromMillisecondsSinceEpoch(baselineStartedAt),
      );

      s.ch.push(
        SessionHistory(
          inReplyTo: 'sync-skew',
          sessionStartedAt: skewedStartedAt,
          events: const [
            UserInputEvt(ts: 2, id: 'skew', text: 'clock-skewed replay'),
          ],
          eos: true,
        ),
      );
      await _settle();
      expect(messages(s.epk).map((r) => r.id), ['skew']);
      expect(
        index(s.epk)?.sessionStartedAt,
        DateTime.fromMillisecondsSinceEpoch(skewedStartedAt),
      );

      s.conn.dispose();
      s.sync.dispose();
    },
  );

  // Plan/32 safety net — a sent message whose echo never comes back must not
  // spin forever. It must also not disappear silently: replace the optimistic
  // bubble with an explicit failure row so the user knows delivery was not
  // confirmed.
  group('no-echo send timeout', () {
    const short = Duration(milliseconds: 60);

    test(
      '(a) pending bubble is replaced with a visible error when no echo arrives',
      () async {
        final s = await setup(pendingSendTimeout: short);
        await s.sync.sendMessage('hello');
        await _settle();
        expect(messages(s.epk), hasLength(1), reason: 'optimistic pending row');
        expect(messages(s.epk).first.pending, isTrue);
        expect(s.sync.isWorking, isTrue);
        expect(s.sync.streaming, isNotNull, reason: 'thinking cursor seeded');

        // No echo — wait past the timeout window.
        await Future<void>.delayed(const Duration(milliseconds: 140));
        await _settle();

        final rows = messages(s.epk);
        expect(rows, hasLength(1), reason: 'visible failure replaces bubble');
        expect(rows.single.role, MsgRole.user);
        expect(rows.single.status, UserMsgStatus.failed);
        expect(rows.single.text, 'hello');
        expect(
          s.sync.isWorking,
          isFalse,
          reason: 'working cleared for this id',
        );
        expect(s.sync.streaming, isNull, reason: 'thinking cursor cleared');
        expect(index(s.epk)?.status, SessionActivity.idle);
        expect(s.sync.debugPendingSendTimerCount, 0);
        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test(
      '(b) echo within the window confirms the row and cancels the timer',
      () async {
        final timers = _PendingTimerScheduler();
        final s = await setup(
          pendingSendTimeout: short,
          pendingSendTimerFactory: timers.schedule,
        );
        await s.sync.sendMessage('hello');
        await _settle();
        expect(s.sync.debugPendingSendTimerCount, 1, reason: 'timer armed');
        final id = s.ch.sent.whereType<UserMessage>().last.id;

        // Echo arrives promptly → confirms + disarms.
        s.ch.push(UserInput(id: id, text: 'hello'));
        await _settle();
        expect(messages(s.epk), hasLength(1));
        expect(
          messages(s.epk).first.pending,
          isFalse,
          reason: 'confirmed by echo',
        );
        expect(
          s.sync.debugPendingSendTimerCount,
          0,
          reason: 'echo cancelled timer',
        );

        // Cross the configured timeout deadline deterministically — a
        // cancelled callback must not replace the confirmed row.
        timers.elapse(short + const Duration(milliseconds: 1));
        await _settle();
        expect(
          messages(s.epk),
          hasLength(1),
          reason: 'row survives the window',
        );
        expect(messages(s.epk).first.pending, isFalse);
        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test(
      '(c) delivery_pending extends the no-echo window without scarring the row',
      () async {
        final timers = _PendingTimerScheduler();
        final s = await setup(
          pendingSendTimeout: short,
          deliveryPendingEchoTimeout: const Duration(milliseconds: 500),
          pendingSendTimerFactory: timers.schedule,
        );
        await s.sync.sendMessage('hello during reload');
        await _settle();
        final id = s.ch.sent.whereType<UserMessage>().last.id;
        expect(s.sync.debugPendingSendTimerCount, 1, reason: 'timer armed');

        s.ch.push(
          ErrorMessage(
            sessionId: s.sessionId,
            inReplyTo: id,
            code: 'delivery_pending',
            message: 'session replacing — message queued for replay',
          ),
        );
        await _settle();
        expect(
          s.sync.debugPendingSendTimerCount,
          1,
          reason: 'original timer was replaced by the extended pending timer',
        );

        // Cross the original 60 ms deadline deterministically. The
        // replacement timer must keep the row pending while replay has time.
        timers.elapse(short + const Duration(milliseconds: 1));
        await _settle();
        expect(messages(s.epk), hasLength(1));
        expect(messages(s.epk).single.pending, isTrue);
        expect(messages(s.epk).single.status, UserMsgStatus.pending);
        expect(s.sync.streaming, isNotNull, reason: 'turn remains pending');

        s.ch.push(UserInput(id: id, text: 'hello during reload'));
        await _settle();
        expect(messages(s.epk), hasLength(1), reason: 'echo dedupes');
        expect(messages(s.epk).single.pending, isFalse);
        expect(s.sync.debugPendingSendTimerCount, 0);
        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test(
      '(d) delivery_pending still fails if no replay echo arrives',
      () async {
        final s = await setup(
          pendingSendTimeout: const Duration(seconds: 5),
          deliveryPendingEchoTimeout: const Duration(milliseconds: 80),
        );
        await s.sync.sendMessage('lost during reload');
        await _settle();
        final id = s.ch.sent.whereType<UserMessage>().last.id;
        s.ch.push(
          ErrorMessage(
            sessionId: s.sessionId,
            inReplyTo: id,
            code: 'delivery_pending',
            message: 'session replacing — message queued for replay',
          ),
        );
        await _settle();

        await Future<void>.delayed(const Duration(milliseconds: 150));
        await _settle();
        expect(messages(s.epk), hasLength(1));
        expect(messages(s.epk).single.role, MsgRole.user);
        expect(messages(s.epk).single.status, UserMsgStatus.failed);
        expect(s.sync.debugPendingSendTimerCount, 0);
        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test(
      '(e) timers are cancelled on session switch and on dispose (no leak)',
      () async {
        // Use a long window so this test observes lifecycle cancellation rather
        // than racing the timeout policy under a loaded full-suite runner.
        const lifecycleWindow = Duration(seconds: 5);
        // Session switch path.
        final s = await setup(pendingSendTimeout: lifecycleWindow);
        await s.sync.sendMessage('one');
        await _settle();
        expect(s.sync.debugPendingSendTimerCount, 1);

        await s.sync.activate('epk_switch_target', 'main');
        await _settle();
        expect(
          s.sync.debugPendingSendTimerCount,
          0,
          reason: 'session switch cancels + clears pending timers',
        );

        // dispose path (fresh service so the switch above doesn't mask it).
        final s2 = await setup(pendingSendTimeout: lifecycleWindow);
        await s2.sync.sendMessage('two');
        await _settle();
        expect(s2.sync.debugPendingSendTimerCount, 1);
        s2.sync.dispose();
        expect(
          s2.sync.debugPendingSendTimerCount,
          0,
          reason: 'dispose cancels + clears pending timers',
        );

        s.conn.dispose();
        s.sync.dispose();
        s2.conn.dispose();
      },
    );

    test(
      '(f) an offline (held-pending) send becomes a visible error too',
      () async {
        // A canonical session was known, then the channel dropped →
        // sendMessage takes the offline path while keeping the session-scoped
        // persistence key.
        final s = await setup(pendingSendTimeout: short);
        final epk = s.epk;
        final retrying = s.conn.statusStream.firstWhere(
          (status) => status is StatusRetrying,
        );
        await s.ch.close();
        await retrying;
        await _settle();

        await s.sync.sendMessage('typed while offline');
        await _settle();
        expect(messages(epk), hasLength(1), reason: 'held pending row written');
        expect(messages(epk).first.pending, isTrue);
        expect(
          s.sync.debugPendingSendTimerCount,
          1,
          reason: 'timeout armed offline',
        );

        await Future<void>.delayed(const Duration(milliseconds: 140));
        await _settle();
        final rows = messages(epk);
        expect(rows, hasLength(1), reason: 'offline failure remains visible');
        expect(rows.single.role, MsgRole.user);
        expect(rows.single.status, UserMsgStatus.failed);
        expect(rows.single.text, 'typed while offline');
        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test(
      '(g) returning to a session fails a bubble already past the window',
      () async {
        // Quick exit then return: the live timer is cancelled on switch-away,
        // but _loadIndex re-arms on return using the saved ts → an already-stale
        // row fires immediately. Covers app-restart + quick-switch orphans.
        final s = await setup(pendingSendTimeout: short);
        await s.sync.sendMessage('hi');
        await _settle();
        expect(messages(s.epk), hasLength(1));

        // Leave quickly → live timer cancelled; row stays pending in the box.
        await s.sync.activate('epk_away_${++_counter}', 'main');
        await _settle();
        expect(
          s.sync.debugPendingSendTimerCount,
          0,
          reason: 'timers cleared on switch',
        );
        expect(
          messages(s.epk),
          hasLength(1),
          reason: 'orphaned row still in box',
        );

        // Time passes beyond the window while away from the session.
        await Future<void>.delayed(const Duration(milliseconds: 140));
        expect(
          messages(s.epk),
          hasLength(1),
          reason: 'no live timer fails it while away',
        );

        // Return → load re-arms by ts → already stale → fails on arrival.
        await s.sync.activate(s.epk, 'main');
        await _settle();
        final rows = messages(s.epk);
        expect(rows, hasLength(1), reason: 'stale pending fails on return');
        expect(rows.single.role, MsgRole.user);
        expect(rows.single.status, UserMsgStatus.failed);
        expect(rows.single.text, 'hi');
        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test('(h) immediate channel send failures become visible errors', () async {
      final s = await setup(pendingSendTimeout: short);
      s.ch.sendFailure = StateError('socket closed');

      await s.sync.sendMessage('hello');
      await _settle();

      expect(s.ch.sent.whereType<UserMessage>(), isEmpty);
      final rows = messages(s.epk);
      expect(rows, hasLength(1));
      expect(rows.single.role, MsgRole.user);
      expect(rows.single.status, UserMsgStatus.failed);
      expect(rows.single.text, 'hello');
      expect(s.sync.isWorking, isFalse);
      expect(s.sync.streaming, isNull);
      expect(s.sync.debugPendingSendTimerCount, 0);
      s.conn.dispose();
      s.sync.dispose();
    });

    test('(i) half-open socket: room marked offline holds the send pending '
        'instead of writing into a dead WS', () async {
      // Reproduces story-app-half-open-socket-swallows-sends-arrives-late:
      // the capture showed the app send into a WS that was StatusOnline
      // but whose room was already proven unreachable (3 missed pongs →
      // _markActiveRoomOffline, equivalent here to a RoomEnded push).
      // The message then sat in the dead send buffer and arrived at the
      // PC minutes late, after the 20s echo timeout had already marked
      // the row failed. The fix gates sendMessage on isRoomLive: when
      // the room is not live, hold the message pending (same as the
      // offline branch) rather than writing into the dead socket.
      final s = await setup(pendingSendTimeout: short);
      expect(s.conn.isRoomLive(s.epk, 'main'), isTrue);
      expect(s.conn.status, isA<StatusOnline>(), reason: 'WS online');

      // A control RoomEnded for the active room marks it offline while
      // the WS stays StatusOnline (the half-open state). The rooms emit
      // is debounced; poll the live-set getter directly (robust across
      // suite ordering) instead of awaiting roomsStream.first.
      s.ch.pushControl(RoomEnded(peer: s.epk, roomId: 'main', sinceTs: 0));
      for (var i = 0; i < 50 && s.conn.isRoomLive(s.epk, 'main'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      expect(s.conn.isRoomLive(s.epk, 'main'), isFalse);
      expect(s.conn.status, isA<StatusOnline>(), reason: 'WS still online');

      // Send into the half-open socket: must be held pending, NOT written
      // to the channel.
      await s.sync.sendMessage('into the dead socket');
      await _settle();

      expect(
        s.ch.sent.whereType<UserMessage>(),
        isEmpty,
        reason: 'must not write into a socket whose room is proven offline',
      );
      final rows = messages(s.epk);
      expect(rows, hasLength(1), reason: 'held-pending row written');
      expect(rows.single.pending, isTrue);
      expect(rows.single.text, 'into the dead socket');
      expect(
        s.sync.debugPendingSendTimerCount,
        1,
        reason: 'timeout armed for the held-pending row',
      );
      // Await the short send timeout so it fires and fails the held row
      // BEFORE dispose — otherwise the pending timer fires into a disposed
      // SyncService mid-suite and contaminates later tests (the shared
      // Hive box + process-wide timer queue outlive a single test).
      await Future<void>.delayed(const Duration(milliseconds: 140));
      await _settle();
      expect(messages(s.epk).single.status, UserMsgStatus.failed);
      expect(s.sync.debugPendingSendTimerCount, 0);
      s.conn.dispose();
      s.sync.dispose();
    });

    test(
      '(ii) relay-only reconnect keeps a held message until RoomsSnapshot confirmation',
      () async {
        final store = _MemoryTranscriptStore();
        final s = await setup(transcriptEventStore: store);
        expect(s.conn.isRoomLive(s.epk, 'main'), isTrue);

        final disconnected = s.conn.statusStream.firstWhere(
          (status) => status is StatusRetrying,
        );
        await s.ch.loseConnection();
        await disconnected.timeout(const Duration(seconds: 1));

        await s.sync.sendMessage('held across relay reconnect');
        final held = store
            .eventsFor(transcriptKeyFor(s.epk))
            .whereType<UserMessageSubmitted>()
            .single;
        expect(held.held, isTrue);
        expect(s.ch.sent.whereType<UserMessage>(), isEmpty);

        final readStarted = Completer<void>();
        final readGate = Completer<void>();
        store
          ..readStarted = readStarted
          ..readGate = readGate;
        final reconnect = _FakeChannel()..defaultSessionId = s.sessionId;
        final staleReconnect = s.conn.roomsStream.firstWhere(
          (_) =>
              s.conn.status is StatusOnline &&
              !s.conn.isRoomLive(s.epk, 'main'),
        );
        s.conn.adopt(
          reconnect,
          PeerRecord(
            remoteEpk: s.epk,
            sessionName: 'Pi',
            relayUrl: 'ws://localhost',
            pairedAt: '2026-01-01T00:00:00Z',
            roomId: 'main',
          ),
        );
        await staleReconnect.timeout(const Duration(seconds: 1));

        expect(
          s.conn.isRoomLive(s.epk, 'main'),
          isFalse,
          reason: 'a relay channel is not fresh Pi-room confirmation',
        );
        expect(
          readStarted.isCompleted,
          isFalse,
          reason: 'held-message recovery must stay gated while room is stale',
        );
        expect(reconnect.sent.whereType<UserMessage>(), isEmpty);

        final resendStarted = Completer<ClientMessage>();
        reconnect.nextSendStarted = resendStarted;
        reconnect.pushControl(
          RoomsSnapshot(
            peer: s.epk,
            rooms: [
              RoomInfo(roomId: 'main', sessionId: s.sessionId, startedAt: 2),
            ],
          ),
        );
        await readStarted.future.timeout(const Duration(seconds: 1));
        expect(
          reconnect.sent.whereType<UserMessage>(),
          isEmpty,
          reason: 'the controlled transcript read has not released the resend',
        );

        readGate.complete();
        final resent = await resendStarted.future.timeout(
          const Duration(seconds: 1),
        );
        expect(s.conn.isRoomLive(s.epk, 'main'), isTrue);
        expect(resent, isA<UserMessage>());
        expect((resent as UserMessage).id, held.clientMessageId);
        expect(resent.text, 'held across relay reconnect');
        expect(
          reconnect.sent.whereType<UserMessage>(),
          hasLength(1),
          reason: 'fresh room confirmation releases the held message once',
        );

        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test('(iii) held-pending message is re-sent on reconnect after timing out '
        '(option 4)', () async {
      // Reproduces story-app-reattempt-held-pending-on-reconnect:
      // option 1's held-pending guard says it 're-attempts on the next
      // healthy connection' but the re-attempt was never implemented. A
      // message held because the room was offline (never written to the
      // channel) just failed at send_timeout and stayed failed — even
      // though re-sending on reconnect would deliver it. Late-confirmation
      // (SessionHistory replay) can't help because the message never
      // reached the Pi. Safe now that the Pi dedupes user_message by
      // (session_id, msg.id) — a re-sent message that already landed is
      // re-echoed without re-waking the agent.
      const short = Duration(milliseconds: 60);
      final s = await setup(pendingSendTimeout: short);
      expect(s.conn.isRoomLive(s.epk, 'main'), isTrue);

      // Mark the room offline (the half-open state) so the send is held.
      s.ch.pushControl(RoomEnded(peer: s.epk, roomId: 'main', sinceTs: 0));
      for (var i = 0; i < 50 && s.conn.isRoomLive(s.epk, 'main'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 4));
      }
      expect(s.conn.isRoomLive(s.epk, 'main'), isFalse);
      expect(s.conn.status, isA<StatusOnline>(), reason: 'WS still online');

      // Send into the offline room: held pending (NOT written to channel).
      await s.sync.sendMessage('held and later re-sent');
      await _settle();
      expect(
        s.ch.sent.whereType<UserMessage>(),
        isEmpty,
        reason: 'held pending — not written to the dead socket',
      );
      final rows = messages(s.epk);
      expect(rows, hasLength(1));
      expect(rows.single.pending, isTrue);

      // Wait for the short send_timeout to fire → row fails.
      await Future<void>.delayed(const Duration(milliseconds: 140));
      await _settle();
      expect(messages(s.epk).single.status, UserMsgStatus.failed);

      // Reconnect with a fresh, healthy channel (room live again).
      final reconnect = _FakeChannel()..defaultSessionId = s.sessionId;
      s.conn.adopt(
        reconnect,
        PeerRecord(
          remoteEpk: s.epk,
          sessionName: 'Pi',
          relayUrl: 'ws://localhost',
          pairedAt: '2026-01-01T00:00:00Z',
        ),
      );
      // The relay re-announces the room on reconnect, re-marking it live
      // (RoomEnded had removed it from _liveRoomIds). Without this, the
      // re-send guard (isRoomLive) would still see the room as offline.
      reconnect.pushControl(
        RoomAnnounced(
          peer: s.epk,
          roomId: 'main',
          startedAt: 1,
          sessionId: s.sessionId,
        ),
      );
      await _settle();
      expect(
        s.conn.isRoomLive(s.epk, 'main'),
        isTrue,
        reason: 'room re-announced on reconnect',
      );
      await _settle();

      // The held-pending message is re-sent on the new channel (with the
      // ORIGINAL id so the echo dedupes). Without option 4, nothing is
      // re-sent and the row stays failed forever.
      final resent = reconnect.sent.whereType<UserMessage>();
      expect(
        resent,
        hasLength(1),
        reason: 'held-pending message re-sent on reconnect',
      );
      expect(resent.single.text, 'held and later re-sent');
      expect(
        resent.single.id,
        rows.single.id,
        reason: 're-send reuses the original id so echo/replay dedupes',
      );
      s.conn.dispose();
      s.sync.dispose();
    });

    test(
      '(iv) a failed held-pending re-send is retryable on a later reconnect',
      () async {
        // Review blocker: the in-flight guard must NOT permanently suppress
        // a message whose re-send failed (stale-liveness, send throw). A
        // later genuinely-healthy reconnect must be able to retry it. The
        // guard is removed on failure so the id is eligible again.
        const short = Duration(milliseconds: 60);
        final s = await setup(pendingSendTimeout: short);

        // Mark the room offline so the send is held.
        s.ch.pushControl(RoomEnded(peer: s.epk, roomId: 'main', sinceTs: 0));
        for (var i = 0; i < 50 && s.conn.isRoomLive(s.epk, 'main'); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 4));
        }
        expect(s.conn.isRoomLive(s.epk, 'main'), isFalse);

        await s.sync.sendMessage('held, fails first re-send');
        await _settle();
        final heldId = messages(s.epk).single.id;

        // Wait for send_timeout → row fails.
        await Future<void>.delayed(const Duration(milliseconds: 140));
        await _settle();
        expect(messages(s.epk).single.status, UserMsgStatus.failed);

        // First reconnect: re-send FAILS (the channel throws).
        final reconnect1 = _FakeChannel()..defaultSessionId = s.sessionId;
        reconnect1.sendFailure = Exception('send failed');
        s.conn.adopt(
          reconnect1,
          PeerRecord(
            remoteEpk: s.epk,
            sessionName: 'Pi',
            relayUrl: 'ws://localhost',
            pairedAt: '2026-01-01T00:00:00Z',
          ),
        );
        reconnect1.pushControl(
          RoomAnnounced(
            peer: s.epk,
            roomId: 'main',
            startedAt: 1,
            sessionId: s.sessionId,
          ),
        );
        await _settle();
        await _settle();
        // The first re-send attempted but failed (no UserMessage recorded
        // because send threw before sent.add).
        expect(reconnect1.sent.whereType<UserMessage>(), isEmpty);
        // Clear the failure so the next reconnect can succeed.
        reconnect1.sendFailure = null;

        // Second reconnect: a genuinely-healthy channel. The message must be
        // retryable (not permanently suppressed by the failed first attempt).
        final reconnect2 = _FakeChannel()..defaultSessionId = s.sessionId;
        s.conn.adopt(
          reconnect2,
          PeerRecord(
            remoteEpk: s.epk,
            sessionName: 'Pi',
            relayUrl: 'ws://localhost',
            pairedAt: '2026-01-01T00:00:00Z',
          ),
        );
        // A fresh RoomAnnounced with a different startedAt so it's not
        // deduped as a no-op re-broadcast (the room was already marked live
        // by reconnect1's announce). working:true models the Pi accepting
        // the re-sent message.
        reconnect2.pushControl(
          RoomAnnounced(
            peer: s.epk,
            roomId: 'main',
            startedAt: 2,
            sessionId: s.sessionId,
            working: true,
          ),
        );
        await _settle();
        await _settle();

        final resent = reconnect2.sent.whereType<UserMessage>();
        expect(
          resent,
          hasLength(1),
          reason: 'failed re-send must be retryable on a later reconnect',
        );
        expect(resent.single.id, heldId, reason: 'reuses the original id');
        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test(
      'a failed held-pending re-send keeps arbitrary exceptions out of diagnostics',
      () async {
        // Privacy canary (feature-diagnostic-privacy-hardening review): the
        // resend failure path once printed `failed: $err` — arbitrary local
        // exception text (paths, tokens, provider responses). The console
        // line must be a fixed category.
        const secret = '/Users/operator/workspace token=secret-7F3A';
        const short = Duration(milliseconds: 60);
        final console = <String>[];
        final originalDebugPrint = debugPrint;
        final s = await setup(pendingSendTimeout: short);
        String heldId = '';
        debugPrint = (message, {wrapWidth}) {
          if (message != null) console.add(message);
        };
        try {
          s.ch.pushControl(RoomEnded(peer: s.epk, roomId: 'main', sinceTs: 0));
          for (var i = 0; i < 50 && s.conn.isRoomLive(s.epk, 'main'); i++) {
            await Future<void>.delayed(const Duration(milliseconds: 4));
          }
          expect(s.conn.isRoomLive(s.epk, 'main'), isFalse);

          await s.sync.sendMessage('held, resend fails with secret');
          await _settle();
          heldId = messages(s.epk).single.id;
          await Future<void>.delayed(const Duration(milliseconds: 140));
          await _settle();

          final reconnect = _FakeChannel()..defaultSessionId = s.sessionId;
          reconnect.sendFailure = Exception('boom $secret');
          s.conn.adopt(
            reconnect,
            PeerRecord(
              remoteEpk: s.epk,
              sessionName: 'Pi',
              relayUrl: 'ws://localhost',
              pairedAt: '2026-01-01T00:00:00Z',
            ),
          );
          reconnect.pushControl(
            RoomAnnounced(
              peer: s.epk,
              roomId: 'main',
              startedAt: 1,
              sessionId: s.sessionId,
            ),
          );
          await _settle();
          await _settle();
          expect(reconnect.sent.whereType<UserMessage>(), isEmpty);
        } finally {
          debugPrint = originalDebugPrint;
        }

        expect(
          console,
          contains('[msg-resend] id=$heldId failed'),
          reason: 'fixed failure category is still emitted',
        );
        final all = console.join('\n');
        expect(all, isNot(contains(secret)));
        expect(all, isNot(contains('boom')));
        s.conn.dispose();
        s.sync.dispose();
      },
    );
  });

  group('turn projection convergence', () {
    test('agent_done projects idle', () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u_agent_done', text: 'hi'));
      await _settle();
      expect(s.sync.turnProjection.working, isTrue);

      s.ch.push(AgentDone(inReplyTo: 'u_agent_done'));
      await _settle();

      expect(s.sync.turnProjection.working, isFalse);
      expect(s.sync.turnProjection.cancelTargetId, isNull);
      s.conn.dispose();
      s.sync.dispose();
    });

    test('provider error projects idle', () async {
      final s = await setup();
      s.ch.push(AgentChunk(inReplyTo: 'u_provider_error', delta: 'partial'));
      await _settle();
      expect(s.sync.turnProjection.working, isTrue);

      s.ch.push(
        ErrorMessage(
          inReplyTo: 'u_provider_error',
          code: 'provider_error',
          message: 'model failed',
        ),
      );
      await _settle();

      expect(s.sync.turnProjection.working, isFalse);
      expect(s.sync.turnProjection.cancelTargetId, isNull);
      s.conn.dispose();
      s.sync.dispose();
    });

    test('cancel/abort projects idle', () async {
      final s = await setup();
      s.ch.push(UserInput(id: 'u_cancel', text: 'stop me'));
      await _settle();
      expect(s.sync.turnProjection.working, isTrue);

      s.ch.push(Cancelled(inReplyTo: 'cancel-1', targetId: 'u_cancel'));
      await _settle();

      expect(s.sync.turnProjection.working, isFalse);
      expect(s.sync.turnProjection.cancelTargetId, isNull);
      s.conn.dispose();
      s.sync.dispose();
    });

    test('send timeout projects idle', () async {
      final s = await setup(
        pendingSendTimeout: const Duration(milliseconds: 120),
      );
      await s.sync.sendMessage('no echo');
      await _settle();
      expect(s.sync.turnProjection.working, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 180));
      await _settle();

      expect(s.sync.turnProjection.working, isFalse);
      expect(s.sync.turnProjection.cancelTargetId, isNull);
      s.conn.dispose();
      s.sync.dispose();
    });

    test('compaction live event projects idle and clears streaming', () async {
      final s = await setup();
      s.ch.push(AgentChunk(inReplyTo: 'u_compact', delta: 'partial'));
      await _settle();
      expect(s.sync.turnProjection.working, isTrue);
      expect(s.sync.streaming, isNotNull);

      s.ch.push(
        Compaction(
          summary: 'compacted context',
          tokensBefore: 12000,
          ts: 1700000000000,
        ),
      );
      await _settle();

      expect(s.sync.turnProjection.working, isFalse);
      expect(s.sync.turnProjection.cancelTargetId, isNull);
      expect(s.sync.streaming, isNull);
      s.conn.dispose();
      s.sync.dispose();
    });

    test(
      'history replay projects idle after a previously active turn',
      () async {
        final s = await setup();
        s.ch.push(AgentChunk(inReplyTo: 'u_history', delta: 'partial'));
        await _settle();
        expect(s.sync.turnProjection.working, isTrue);

        s.ch.push(
          SessionHistory(
            sessionId: s.sessionId,
            inReplyTo: 'sync-history-terminal',
            sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
            events: const [
              UserInputEvt(ts: 1, id: 'u_history', text: 'hi'),
              AgentMessageEvt(ts: 2, inReplyTo: 'u_history', text: 'done'),
            ],
            eos: true,
          ),
        );
        await _settle();

        expect(s.sync.turnProjection.working, isFalse);
        expect(s.sync.turnProjection.cancelTargetId, isNull);
        expect(s.sync.streaming, isNull);
        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test(
      'compaction replay projects idle after a previously active turn',
      () async {
        final s = await setup();
        s.ch.push(AgentChunk(inReplyTo: 'u_history_compact', delta: 'partial'));
        await _settle();
        expect(s.sync.turnProjection.working, isTrue);

        s.ch.push(
          SessionHistory(
            sessionId: s.sessionId,
            inReplyTo: 'sync-history-compaction-terminal',
            sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
            events: const [
              CompactionEvt(
                ts: 1,
                summary: 'compacted from replay',
                tokensBefore: 1000,
              ),
            ],
            eos: true,
          ),
        );
        await _settle();

        expect(s.sync.turnProjection.working, isFalse);
        expect(s.sync.turnProjection.cancelTargetId, isNull);
        expect(s.sync.streaming, isNull);
        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test('session switch projects idle', () async {
      final s = await setup();
      s.ch.push(AgentChunk(inReplyTo: 'u_switch', delta: 'partial'));
      await _settle();
      expect(s.sync.turnProjection.working, isTrue);

      await s.sync.activate('epk_projection_switch', 'main');
      await _settle();

      expect(s.sync.turnProjection.working, isFalse);
      expect(s.sync.turnProjection.cancelTargetId, isNull);
      s.conn.dispose();
      s.sync.dispose();
    });

    test('connection loss and reconnect project idle', () async {
      final s = await setup();
      final retrying = s.conn.statusStream.firstWhere(
        (status) => status is StatusRetrying,
      );
      s.ch.push(AgentChunk(inReplyTo: 'u_disconnect', delta: 'partial'));
      await _settle();
      expect(s.sync.turnProjection.working, isTrue);

      await s.ch.close();
      await retrying;
      await _settle();
      expect(s.sync.turnProjection.working, isFalse);
      expect(s.sync.turnProjection.cancelTargetId, isNull);

      final reconnect = _FakeChannel()..defaultSessionId = s.sessionId;
      s.conn.adopt(
        reconnect,
        PeerRecord(
          remoteEpk: s.epk,
          sessionName: 'Pi',
          relayUrl: 'ws://localhost',
          pairedAt: '2026-01-01T00:00:00Z',
        ),
      );
      await _settle();
      expect(s.sync.turnProjection.working, isFalse);
      expect(s.sync.turnProjection.cancelTargetId, isNull);
      s.conn.dispose();
      s.sync.dispose();
    });

    test('dispose projects idle and closes turn stream', () async {
      final s = await setup();
      s.ch.push(AgentChunk(inReplyTo: 'u_dispose', delta: 'partial'));
      await _settle();
      expect(s.sync.turnProjection.working, isTrue);
      final done = expectLater(
        s.sync.turnViewStream,
        emitsInOrder([
          isA<TranscriptTurnView>()
              .having((turn) => turn.working, 'working', isFalse)
              .having((turn) => turn.replyTo, 'replyTo', isNull),
          emitsDone,
        ]),
      );

      s.sync.dispose();

      expect(s.sync.turnProjection.working, isFalse);
      expect(s.sync.turnProjection.cancelTargetId, isNull);
      await done;
      s.conn.dispose();
    });
  });

  // Foreign-session / replacement-race tolerance for `session_mismatch`.
  // See story-foreign-session-user-message-tolerance.
  group('session_mismatch tolerance', () {
    test(
      'foreign duplicate Pi mismatch reply is dropped without a warning row',
      () async {
        final s = await setup();
        await s.sync.sendMessage('hello duplicate pi');
        await _settle();
        final sentId = s.ch.sent.whereType<UserMessage>().last.id;

        // A duplicate/idle Pi with a DIFFERENT session id rejects the
        // fanned-out message. Its error carries the rejecting Pi's session,
        // which differs from the app's active ref → SessionGate drops it.
        s.ch.push(
          ErrorMessage(
            inReplyTo: sentId,
            code: 'session_mismatch',
            message: 'Session-scoped command targets a stale session',
            sessionId: 'session_foreign_duplicate',
          ),
        );
        await _settle();

        final assistantTexts = messages(
          s.epk,
        ).where((m) => m.role == MsgRole.assistant).map((m) => m.text);
        expect(
          assistantTexts,
          isNot(contains(startsWith('⚠ session_mismatch'))),
        );
        expect(assistantTexts, isEmpty);
        // Active session is unchanged; no sync targets the foreign id.
        expect(s.sync.activeSessionRef?.sessionId, s.sessionId);
        expect(
          s.ch.sent.whereType<SessionSync>(),
          everyElement(
            predicate<SessionSync>(
              (m) => m.sessionId != 'session_foreign_duplicate',
            ),
          ),
        );
        // The foreign mismatch must not disturb the pending send's timer —
        // it stays armed for its normal echo/timeout owner to resolve.
        expect(s.sync.debugPendingSendTimerCount, 1);
        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test(
      'accepted current-session mismatch reply renders no warning row either',
      () async {
        // The narrow race: room metadata rebinds the app to the rejecting
        // Pi's session BEFORE its mismatch error arrives, so SessionGate
        // accepts the error. It must still not render a ⚠ row.
        final s = await setup();
        await s.sync.sendMessage('hello race window');
        await _settle();
        final sentId = s.ch.sent.whereType<UserMessage>().last.id;

        // Push the mismatch error after the app is bound to THIS session —
        // the gate accepts it because session_id matches.
        s.ch.push(
          ErrorMessage(
            inReplyTo: sentId,
            code: 'session_mismatch',
            message: 'Session-scoped command targets a stale session',
            sessionId: s.sessionId,
          ),
        );
        await _settle();

        final assistantTexts = messages(
          s.epk,
        ).where((m) => m.role == MsgRole.assistant).map((m) => m.text);
        expect(
          assistantTexts,
          isNot(contains(startsWith('⚠ session_mismatch'))),
        );
        expect(assistantTexts, isEmpty);
        s.conn.dispose();
        s.sync.dispose();
      },
    );

    test(
      'canonical room-metadata session rotation triggers session_sync for the new session',
      () async {
        final s = await setup();

        // Snapshot the sent-message count before rotation so we can assert
        // that every sync sent AFTER rotation targets the new session.
        final sentBeforeRotation = s.ch.sent.length;

        // Rotate to a new canonical session id via room metadata (PairOk).
        const rotatedSession = 'session-rotated-for-resync';
        _sessionByEpk[s.epk] = rotatedSession;
        s.ch.defaultSessionId = rotatedSession;
        s.ch.pushRaw(
          PairOk(
            inReplyTo: 'pair-rotated-resync',
            sessionName: 'Pi',
            sessionStartedAt: DateTime.now().millisecondsSinceEpoch,
            roomId: 'main',
            sessionId: rotatedSession,
          ),
        );
        await _settle();
        await _settle();
        await _settle();
        await _settle();

        // The newly canonical session must receive a session_sync.
        expect(s.sync.activeSessionRef?.sessionId, rotatedSession);
        final syncsAfterRotation = s.ch.sent
            .skip(sentBeforeRotation)
            .whereType<SessionSync>();
        expect(syncsAfterRotation, isNotEmpty);
        // Every sync sent after the rotation targets the new session — never
        // the stale old id.
        expect(
          syncsAfterRotation,
          everyElement(
            predicate<SessionSync>((m) => m.sessionId == rotatedSession),
          ),
        );
        s.conn.dispose();
        s.sync.dispose();
      },
    );
  });
}

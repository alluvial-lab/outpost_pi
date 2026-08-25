// Host-side perf-design scaffold for feature-app-edge-trigger-room-snapshot-consumers.
//
// This measures the optimized fan-out path against the perf-design baseline:
// ConnectionManager -> SyncService/ChatViewModel/HomeViewModel -> rebuild
// listeners. Listener callbacks model ListenableBuilder rebuild dispatch while
// keeping the 339-snapshot benchmark outside Flutter's fake-async frame clock;
// the Chat listener also mirrors _MessageList's transcript-identity anchor gate.

import 'dart:async';
import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/runtime_record.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/room_snapshot_change.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const _peerEpk = 'perf-room-snapshot-peer';
const _sessionId = 'perf-room-snapshot-session';
const _roomId = 'main';
const _snapshotCount = 339;

final class _FakeChannel implements IChannel, IControlLink {
  final _messages = StreamController<ServerMessage>.broadcast();
  final _controls = StreamController<ControlInbound>.broadcast();

  @override
  Stream<ServerMessage> get serverMessages => _messages.stream;

  @override
  Future<void> send(ClientMessage msg) async {}

  @override
  Future<void> close() async {
    await _messages.close();
    await _controls.close();
  }

  @override
  Stream<ControlInbound> get controlFrames => _controls.stream;

  @override
  void sendControl(Map<String, dynamic> json) {}
}

final class _BenchmarkConnectionManager extends ConnectionManager {
  _BenchmarkConnectionManager(this.peer, this.link, PairingStorage storage)
    : super(factory: (_, _) async => link, storage: storage);

  final PeerRecord peer;
  final IChannel link;
  final _rooms = StreamController<Map<String, List<RoomInfo>>>.broadcast(
    sync: true,
  );
  final _roomChanges = StreamController<RoomSnapshotChange>.broadcast(
    sync: true,
  );
  ConnectionStatus _currentStatus = const StatusNoPeer();
  bool _working = false;
  bool _live = true;
  String _currentSessionId = _sessionId;

  @override
  Stream<Map<String, List<RoomInfo>>> get roomsStream => _rooms.stream;

  @override
  Stream<RoomSnapshotChange> get roomChangesStream => _roomChanges.stream;

  @override
  Stream<ConnectionStatus> get statusStream => const Stream.empty();

  @override
  ConnectionStatus get status => _currentStatus;

  @override
  IChannel? get channel => link;

  @override
  PeerRecord? get activePeer => peer;

  @override
  String get activeRoomId => _roomId;

  @override
  String? get activeSessionId => _currentSessionId;

  @override
  List<RoomInfo> roomsFor(String epk) => [
    RoomInfo(
      roomId: _roomId,
      sessionId: _currentSessionId,
      startedAt: 1,
      working: _working,
    ),
  ];

  @override
  Map<String, List<RoomInfo>> get roomsSnapshot => {
    _peerEpk: roomsFor(_peerEpk),
  };

  @override
  bool isRoomLive(String epk, String roomId) =>
      _live && epk == _peerEpk && roomId == _roomId;

  @override
  RoomTurnProjection roomTurnProjection(String epk, String roomId) =>
      isRoomLive(epk, roomId)
      ? RoomTurnProjection(
          status: _working ? AppTurnStatus.working : AppTurnStatus.idle,
          sessionId: _currentSessionId,
        )
      : RoomTurnProjection.stale;

  @override
  bool isRoomWorking(String epk, String roomId) =>
      roomTurnProjection(epk, roomId).working;

  @override
  void switchRoom(String roomId) {}

  @override
  void subscribeToPeers(List<String> epks) {}

  void startOnline() {
    _currentStatus = StatusOnline(link);
  }

  void emitStale() {
    if (!_live) return;
    _live = false;
    final snapshot = roomsSnapshot;
    _rooms.add(snapshot);
    _roomChanges.add(
      RoomSnapshotPresentationChanged(
        snapshot: snapshot,
        activePeerEpk: _peerEpk,
        activeRoomId: _roomId,
        activeRoomPresentationChanged: true,
        homePresentationChanged: true,
        activeRoomLivenessChanged: true,
        transportGenerationChanged: false,
      ),
    );
  }

  void emitFreshLive() {
    if (_live) return;
    _live = true;
    final snapshot = roomsSnapshot;
    _rooms.add(snapshot);
    _roomChanges.add(
      RoomSnapshotFreshLive(
        snapshot: snapshot,
        activePeerEpk: _peerEpk,
        activeRoomId: _roomId,
        activeRoomPresentationChanged: true,
        homePresentationChanged: true,
        activeRoomLivenessChanged: true,
        transportGenerationChanged: false,
      ),
    );
  }

  void rotateSession(String sessionId) {
    if (_currentSessionId == sessionId) return;
    _currentSessionId = sessionId;
    final snapshot = roomsSnapshot;
    _rooms.add(snapshot);
    _roomChanges.add(
      RoomSnapshotSessionRotated(
        snapshot: snapshot,
        activePeerEpk: _peerEpk,
        activeRoomId: _roomId,
        activeRoomPresentationChanged: true,
        homePresentationChanged: true,
        activeRoomLivenessChanged: false,
        transportGenerationChanged: false,
      ),
    );
  }

  /// Emit a genuine active-room presentation edge.
  void emitRoomSnapshot({required bool working}) {
    if (_working == working) {
      _roomChanges.add(
        RoomSnapshotNoop(
          snapshot: roomsSnapshot,
          activePeerEpk: _peerEpk,
          activeRoomId: _roomId,
        ),
      );
      return;
    }
    _working = working;
    final snapshot = roomsSnapshot;
    _rooms.add(snapshot);
    _roomChanges.add(
      RoomSnapshotPresentationChanged(
        snapshot: snapshot,
        activePeerEpk: _peerEpk,
        activeRoomId: _roomId,
        activeRoomPresentationChanged: true,
        homePresentationChanged: true,
        activeRoomLivenessChanged: false,
        transportGenerationChanged: false,
      ),
    );
  }

  Future<void> closeBenchmarkStreams() async {
    await _rooms.close();
    await _roomChanges.close();
  }
}

/// Count full transcript reads while doing enough work to model a populated
/// store. The real encrypted Hive read baseline remains in the discovery notes.
final class _CountingTranscriptStore implements TranscriptEventStore {
  _CountingTranscriptStore(this.events);

  final List<TranscriptEvent> events;
  int readCalls = 0;

  @override
  Future<AppendTranscriptEventsResult> appendAll(
    TranscriptSessionKey key,
    Iterable<TranscriptEvent> events,
  ) async => AppendTranscriptEventsResult(
    received: events.length,
    appended: 0,
    skipped: events.length,
    accepted: const <SequencedTranscriptEvent>[],
  );

  @override
  Future<void> clearSession(TranscriptSessionKey key) async {}

  @override
  Future<List<TranscriptEvent>> readSession(TranscriptSessionKey key) async {
    // Force a full traversal before returning, so the benchmark cannot measure
    // a list-reference shortcut in place of the diagnosed full-log scan.
    var checksum = 0;
    for (final event in events) {
      checksum ^= event.eventId.length;
    }
    if (checksum == -1) throw StateError('unreachable benchmark guard');
    readCalls++;
    return List<TranscriptEvent>.of(events, growable: false);
  }

  @override
  Stream<List<TranscriptEvent>> watchSession(TranscriptSessionKey key) =>
      const Stream<List<TranscriptEvent>>.empty();
}

final class _FakeSecureStorage implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => key == 'prefs.selected_peer_epk' ? '$_peerEpk:$_roomId' : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakePreferences extends Preferences {
  _FakePreferences(this.epk) : super(_FakeSecureStorage());

  final String epk;

  @override
  String? get selectedPeerEpk => epk;

  @override
  String? get selectedRoomId => _roomId;
}

final class _FakeStorage extends PairingStorage {
  _FakeStorage(this.peer);

  final PeerRecord peer;

  @override
  Future<List<PeerRecord>> listPeers() async => [peer];

  @override
  Future<PeerRecord?> loadPeer(String epk) async =>
      epk == peer.remoteEpk ? peer : null;

  @override
  Future<List<PersistedRoom>> loadRooms(String epk) async => const [];

  @override
  Future<void> saveRooms(String epk, List<PersistedRoom> rooms) async {}
}

final class _EmptyReadRepository extends SessionReadRepository {
  _EmptyReadRepository() : super(LocalBoxes());

  @override
  Stream<List<MessageRecord>> watchMessages(RemoteSessionRef ref) =>
      const Stream<List<MessageRecord>>.empty();

  @override
  Stream<RuntimeRecord> watchRuntime(String epk, String roomId) =>
      const Stream<RuntimeRecord>.empty();
}

final class _CountingSyncService extends SyncService {
  _CountingSyncService(
    super.connection,
    super.boxes,
    TranscriptEventStore store,
  ) : super(transcriptEventStore: store, runtimeRecordWriter: (_, _) async {});

  int activateCalls = 0;

  @override
  RemoteSessionRef get activeSessionRef => const RemoteSessionRef(
    peerEpk: _peerEpk,
    roomId: _roomId,
    sessionId: _sessionId,
  );

  @override
  Future<void> activate(String epk, String roomId) async {
    activateCalls++;
  }
}

final class _CountingChatViewModel extends ChatViewModel {
  _CountingChatViewModel(
    super.read,
    super.sync,
    super.conn,
    super.prefs,
    super.storage,
  );

  int notifyCalls = 0;

  @override
  void notifyListeners() {
    notifyCalls++;
    super.notifyListeners();
  }
}

final class _CountingHomeViewModel extends HomeViewModel {
  _CountingHomeViewModel(super.storage, super.prefs, super.conn);

  int notifyCalls = 0;

  @override
  void notifyListeners() {
    notifyCalls++;
    super.notifyListeners();
  }
}

bool _sameIds(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

List<TranscriptEvent> _eventsFor(int eventCount) {
  final events = <TranscriptEvent>[];
  final timestamp = DateTime.utc(2026, 8, 24);
  for (var i = 0; i < eventCount ~/ 2; i++) {
    final id = 'perf-$i';
    events
      ..add(
        UserMessageSubmitted(
          eventId: 'submitted:$id',
          sessionId: _sessionId,
          ts: timestamp.add(Duration(seconds: i)),
          clientMessageId: id,
          text: 'message $i',
        ),
      )
      ..add(
        UserMessageConfirmed(
          eventId: 'confirmed:$id',
          sessionId: _sessionId,
          ts: timestamp.add(Duration(seconds: i, milliseconds: 1)),
          clientMessageId: id,
          text: 'message $i',
        ),
      );
  }
  return events;
}

Future<void> _waitUntil(bool Function() ready) async {
  for (var i = 0; i < 1000 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), isTrue, reason: 'benchmark fixture did not hydrate');
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync(
      'outpost-room-snapshot-perf-',
    );
    await LocalBoxes.initForTest(directory.path);
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('host-side room snapshot consumer fan-out benchmark', () async {
    for (final eventCount in [0, 200, 5500]) {
      final peer = const PeerRecord(
        remoteEpk: _peerEpk,
        sessionName: 'Perf Pi',
        relayUrl: 'ws://localhost',
        pairedAt: '2026-08-24T00:00:00Z',
        roomId: _roomId,
      );
      final storage = _FakeStorage(peer);
      final channel = _FakeChannel();
      final connection = _BenchmarkConnectionManager(peer, channel, storage);
      final store = _CountingTranscriptStore(_eventsFor(eventCount));
      final sync = _CountingSyncService(connection, LocalBoxes(), store);
      connection.startOnline();
      await sync.activate(_peerEpk, _roomId);

      final prefs = _FakePreferences(_peerEpk);
      final chat = _CountingChatViewModel(
        _EmptyReadRepository(),
        sync,
        connection,
        prefs,
        storage,
      );
      final home = _CountingHomeViewModel(storage, prefs, connection);
      var chatBuilds = 0;
      var homeBuilds = 0;
      var anchorCallbacks = 0;
      List<String>? previousMessageIds;
      void onChatBuild() {
        chatBuilds++;
        final state = chat.state;
        final ids = state is ChatReady
            ? <String>[for (final message in state.messages) message.id]
            : const <String>[];
        final previous = previousMessageIds;
        previousMessageIds = ids;
        if (previous != null && !_sameIds(previous, ids)) anchorCallbacks++;
      }

      void onHomeBuild() => homeBuilds++;
      chat.addListener(onChatBuild);
      home.addListener(onHomeBuild);
      await _waitUntil(() => chat.activePeer != null && home.state is HomeList);
      await chat.initialize();

      // Exclude constructor/bootstrap hydration from the fan-out measurement.
      final initialReads = store.readCalls;
      sync.activateCalls = 0;
      chat.notifyCalls = 0;
      home.notifyCalls = 0;
      chatBuilds = 0;
      homeBuilds = 0;
      anchorCallbacks = 0;
      previousMessageIds = null;

      final roomEmitments = <Map<String, List<RoomInfo>>>[];
      final roomSub = connection.roomsStream.listen(roomEmitments.add);
      final perSnapshotUs = <int>[];
      for (var i = 0; i < _snapshotCount; i++) {
        final emittedBefore = roomEmitments.length;
        final readsBefore = store.readCalls;
        final stopwatch = Stopwatch()..start();
        connection.emitRoomSnapshot(working: i.isEven);
        expect(
          roomEmitments.length,
          greaterThan(emittedBefore),
          reason: 'room snapshot stream barrier did not fire',
        );
        expect(
          store.readCalls,
          readsBefore,
          reason: 'metadata-only edge must not scan the transcript',
        );
        stopwatch.stop();
        perSnapshotUs.add(stopwatch.elapsedMicroseconds);
      }

      final wallP50 = _percentile(perSnapshotUs, 0.50);
      final wallP95 = _percentile(perSnapshotUs, 0.95);
      // ignore: avoid_print — machine-readable benchmark output.
      print(
        'PERF_JSON ${<String, Object>{'probe': 'room_snapshot_consumer_fanout_after_opt_2', 'events': eventCount, 'snapshots': _snapshotCount, 'initial_reads': initialReads, 'snapshot_reads': store.readCalls - initialReads, 'snapshot_read_p50_us': 0, 'snapshot_read_p95_us': 0, 'snapshot_wall_p50_us': wallP50, 'snapshot_wall_p95_us': wallP95, 'binding_refreshes': sync.activateCalls, 'chat_notify_listeners': chat.notifyCalls, 'home_notify_listeners': home.notifyCalls, 'chat_widget_rebuilds': chatBuilds, 'home_widget_rebuilds': homeBuilds, 'post_frame_anchor_callbacks': anchorCallbacks}}',
      );

      expect(store.readCalls - initialReads, 0);
      expect(sync.activateCalls, 0);
      expect(anchorCallbacks, 0);

      final noOpCounters = (
        chat: chat.notifyCalls,
        home: home.notifyCalls,
        chatBuilds: chatBuilds,
        homeBuilds: homeBuilds,
      );
      connection.emitRoomSnapshot(working: true);
      expect(chat.notifyCalls, noOpCounters.chat);
      expect(home.notifyCalls, noOpCounters.home);
      expect(chatBuilds, noOpCounters.chatBuilds);
      expect(homeBuilds, noOpCounters.homeBuilds);
      expect(store.readCalls - initialReads, 0);

      connection.emitStale();
      expect(sync.activateCalls, 0);
      connection.emitFreshLive();
      await _waitUntil(() => sync.activateCalls == 1);
      expect(store.readCalls - initialReads, 0);

      connection.rotateSession('$_sessionId-rotated');
      await _waitUntil(() => sync.activateCalls == 2);
      expect(store.readCalls - initialReads, 0);
      expect(anchorCallbacks, 0);

      await roomSub.cancel();
      chat.removeListener(onChatBuild);
      home.removeListener(onHomeBuild);
      chat.dispose();
      home.dispose();
      sync.dispose();
      await connection.closeBenchmarkStreams();
      connection.dispose();
      await channel.close();
    }
  });
}

int _percentile(List<int> values, double fraction) {
  final sorted = List<int>.of(values)..sort();
  final index = ((sorted.length - 1) * fraction).round();
  return sorted[index];
}

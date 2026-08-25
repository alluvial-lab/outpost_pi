// Plan/32g — the Chat AppBar's line 2 (paired-device name) must render from the
// `initialDevice` hint Home passes, immediately, WITHOUT waiting for the async
// PeerRecord. With no peer bound (activePeer == null), the device label still
// shows — proving the subtitle no longer depends on the async load (no flicker).

import 'dart:async';
import 'dart:io';

import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/images/image_picker_service.dart';
import 'package:app/data/local/boxes.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/voice/speech_service.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/chat/attachment/viewmodels/attachment_viewmodel.dart';
import 'package:app/ui/chat/chat_page.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/chat/voice/viewmodels/voice_input_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

class _FakeChannel implements IChannel {
  final _ctrl = StreamController<ServerMessage>.broadcast();
  @override
  Stream<ServerMessage> get serverMessages => _ctrl.stream;
  @override
  Future<void> send(ClientMessage msg) async {}
  @override
  Future<void> close() => _ctrl.close();
}

/// No peer paired → ChatViewModel stays with activePeer == null (the case we
/// want: the subtitle must come from initialDevice, not the PeerRecord).
class _FakeStorage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => const [];
  @override
  Future<PeerRecord?> loadPeer(String epk) async => null;
}

class _CountingChatViewModel extends ChatViewModel {
  _CountingChatViewModel(
    super.read,
    super.sync,
    super.conn,
    super.prefs,
    super.storage,
  );

  int resumeRefreshes = 0;

  @override
  Future<void> refreshOnResume() async {
    resumeRefreshes += 1;
  }

  void show(ChatReady ready) => emit(ready);
}

class _FakeSecureStorage implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSpeech implements SpeechService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakePicker implements IImagePickerService {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('rp_v2_chatpage_');
    await LocalBoxes.initForTest(dir.path);
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets(
    'backfill preserves a non-bottom viewport anchor and marks continuation',
    (tester) async {
      final conn = ConnectionManager(
        factory: (_, _) async => _FakeChannel(),
        storage: _FakeStorage(),
      );
      final boxes = LocalBoxes();
      final sync = SyncService(conn, boxes);
      final read = SessionReadRepository(boxes);
      final prefs = Preferences(_FakeSecureStorage());
      final actions = ActionsRepository(conn);
      final vm = _CountingChatViewModel(
        read,
        sync,
        conn,
        prefs,
        _FakeStorage(),
      );
      final voice = VoiceInputViewModel(_FakeSpeech());
      final attach = AttachmentViewModel(_FakePicker(), actions);
      final selection = SessionSelection();
      const online = ChatStatusProjection(
        transport: ChatTransportOnline(roomId: 'main'),
        turn: AppTurnProjection.idle,
        steering: NoSteering(),
      );
      const retrying = ChatStatusProjection(
        transport: ChatTransportRetrying(
          attempt: 0,
          nextRetry: Duration(seconds: 1),
        ),
        turn: AppTurnProjection.stale,
        steering: NoSteering(),
      );
      List<ChatMessage> transcript(int first, int last) => [
        for (var i = first; i <= last; i++)
          AssistantMsg(id: 'm$i', text: 'message $i\ncontinuation line $i'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ChatViewModel>.value(value: vm),
              ChangeNotifierProvider<VoiceInputViewModel>.value(value: voice),
              ChangeNotifierProvider<AttachmentViewModel>.value(value: attach),
              ChangeNotifierProvider<Preferences>.value(value: prefs),
              ChangeNotifierProvider<SessionSelection>.value(value: selection),
            ],
            child: const ChatPage(initialOnline: true),
          ),
        ),
      );
      await tester.pump();
      vm.show(ChatReady(messages: transcript(5, 34), status: online));
      await tester.pump();

      final scrollable = find.byType(Scrollable).first;
      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pump();
      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(2),
        reason: 'the anchor case must not exercise the bottom-pinned branch',
      );
      final viewport = tester.getRect(scrollable);
      Finder? anchor;
      var before = double.infinity;
      for (var i = 5; i <= 34; i++) {
        final candidate = find.text('message $i\ncontinuation line $i');
        if (candidate.evaluate().isEmpty) continue;
        final rect = tester.getRect(candidate);
        if (rect.bottom > viewport.top &&
            rect.top < viewport.bottom &&
            rect.top < before) {
          anchor = candidate;
          before = rect.top;
        }
      }
      expect(anchor, isNotNull);

      vm.show(ChatReady(messages: transcript(5, 34), status: retrying));
      await tester.pump();
      vm.show(ChatReady(messages: transcript(5, 34), status: online));
      await tester.pump();
      vm.show(ChatReady(messages: transcript(0, 34), status: online));
      await tester.pump();
      await tester.pump();

      expect(tester.getTopLeft(anchor!).dy, closeTo(before, 1));
      expect(find.text('Reconnected · transcript updated'), findsOneWidget);

      final position = tester.state<ScrollableState>(scrollable).position;
      final offsetBeforeContinuedScroll = position.pixels;
      for (var first = -1; first >= -5; first--) {
        await tester.drag(scrollable, const Offset(0, 80));
        await tester.pump();
        vm.show(ChatReady(messages: transcript(first, 34), status: online));
        await tester.pump();
        await tester.pump();
      }
      expect(
        position.pixels,
        greaterThan(offsetBeforeContinuedScroll),
        reason: 'user scroll must accumulate while backfill keeps inserting',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('m0')),
        120,
        scrollable: scrollable,
        maxScrolls: 20,
      );
      expect(
        find.byKey(const ValueKey<String>('m0')),
        findsOneWidget,
        reason: 'an older bubble remains reachable during continued inserts',
      );

      position.jumpTo(position.minScrollExtent);
      await tester.pump();
      vm.show(ChatReady(messages: transcript(0, 34), status: retrying));
      await tester.pump();
      vm.show(ChatReady(messages: transcript(0, 34), status: online));
      await tester.pump();
      vm.show(ChatReady(messages: transcript(0, 36), status: online));
      await tester.pump();
      await tester.pump();
      expect(position.pixels, closeTo(position.minScrollExtent, 0.1));
      expect(
        find.text('message 36\ncontinuation line 36'),
        findsOneWidget,
        reason: 'later-turn hydration stays visible while bottom-pinned',
      );

      // Hold update A at the build boundary so its post-frame anchor restore
      // is queued but has not run. A real drag must invalidate that restore.
      await tester.drag(scrollable, const Offset(0, 260));
      await tester.pump();
      expect(position.pixels, greaterThan(position.minScrollExtent + 2));
      vm.show(ChatReady(messages: transcript(-1, 36), status: online));
      await tester.pump(Duration.zero, EnginePhase.build);
      await tester.drag(scrollable, const Offset(0, 120), touchSlopY: 0);
      final userOffset = position.pixels;
      await tester.pump();
      expect(
        position.pixels,
        closeTo(userOffset, 0.1),
        reason: 'the queued restore cannot fight a newer user gesture',
      );

      // Queue A and B before either post-frame restore runs. The revision fence
      // must leave the viewport at B's latest captured anchor, not replay A.
      final viewportBeforeBurst = tester.getRect(scrollable);
      Finder? burstAnchor;
      var burstAnchorTop = double.infinity;
      for (var i = -1; i <= 36; i++) {
        final candidate = find.text('message $i\ncontinuation line $i');
        if (candidate.evaluate().isEmpty) continue;
        final rect = tester.getRect(candidate);
        if (rect.bottom > viewportBeforeBurst.top &&
            rect.top < viewportBeforeBurst.bottom &&
            rect.top < burstAnchorTop) {
          burstAnchor = candidate;
          burstAnchorTop = rect.top;
        }
      }
      expect(burstAnchor, isNotNull);
      vm.show(ChatReady(messages: transcript(-2, 36), status: online));
      vm.show(ChatReady(messages: transcript(-4, 36), status: online));
      await tester.pump();
      await tester.pump();
      expect(
        tester.getTopLeft(burstAnchor!).dy,
        closeTo(burstAnchorTop, 1),
        reason: 'only the newest queued transcript restore may apply',
      );

      // Exercise the exact historical-edge boundary. The old first row stays
      // at the same visual offset when a new oldest row extends maxScrollExtent.
      for (var i = 0; i < 3; i++) {
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
      }
      final exactAnchor = find.byKey(const ValueKey<String>('m-4'));
      expect(exactAnchor, findsOneWidget);
      final exactTop = tester.getTopLeft(exactAnchor).dy;
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.1));
      vm.show(ChatReady(messages: transcript(-5, 36), status: online));
      await tester.pump();
      await tester.pump();
      expect(tester.getTopLeft(exactAnchor).dy, closeTo(exactTop, 1));

      position.jumpTo(position.minScrollExtent);
      await tester.pump();
      vm.show(ChatReady(messages: transcript(-6, 36), status: online));
      await tester.pump();
      await tester.pump();
      expect(
        position.pixels,
        closeTo(position.minScrollExtent, 0.1),
        reason: 'the exact bottom boundary remains pinned',
      );

      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      attach.dispose();
      voice.dispose();
      actions.dispose();
      sync.dispose();
      selection.dispose();
      conn.dispose();
    },
  );

  testWidgets(
    'completed hydration materializes the whole assistant bubble without streaming chrome',
    (tester) async {
      final conn = ConnectionManager(
        factory: (_, _) async => _FakeChannel(),
        storage: _FakeStorage(),
      );
      final boxes = LocalBoxes();
      final sync = SyncService(conn, boxes);
      final prefs = Preferences(_FakeSecureStorage());
      final actions = ActionsRepository(conn);
      final vm = _CountingChatViewModel(
        SessionReadRepository(boxes),
        sync,
        conn,
        prefs,
        _FakeStorage(),
      );
      final voice = VoiceInputViewModel(_FakeSpeech());
      final attach = AttachmentViewModel(_FakePicker(), actions);
      final selection = SessionSelection();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ChatViewModel>.value(value: vm),
              ChangeNotifierProvider<VoiceInputViewModel>.value(value: voice),
              ChangeNotifierProvider<AttachmentViewModel>.value(value: attach),
              ChangeNotifierProvider<Preferences>.value(value: prefs),
              ChangeNotifierProvider<SessionSelection>.value(value: selection),
            ],
            child: const ChatPage(initialOnline: true),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('streaming')), findsNothing);

      vm.show(
        const ChatReady(
          messages: [
            UserMsg(id: 'hydrated-u1', text: 'replayed prompt'),
            AssistantMsg(id: 'hydrated-a1', text: 'complete replay'),
          ],
          status: ChatStatusProjection(
            transport: ChatTransportOnline(roomId: 'main'),
            turn: AppTurnProjection.idle,
            steering: NoSteering(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('complete replay'), findsOneWidget);
      expect(find.byKey(const ValueKey('streaming')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      attach.dispose();
      voice.dispose();
      actions.dispose();
      sync.dispose();
      selection.dispose();
      conn.dispose();
    },
  );

  testWidgets(
    'AppBar line 2 shows the device from initialDevice immediately — no '
    'PeerRecord needed (plan/32g)',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final conn = ConnectionManager(
        factory: (_, _) async => _FakeChannel(),
        storage: _FakeStorage(),
      );
      final boxes = LocalBoxes();
      final sync = SyncService(conn, boxes);
      final read = SessionReadRepository(boxes);
      final prefs = Preferences(_FakeSecureStorage()); // no selected peer
      final actions = ActionsRepository(conn);
      final vm = _CountingChatViewModel(
        read,
        sync,
        conn,
        prefs,
        _FakeStorage(),
      );
      final voice = VoiceInputViewModel(_FakeSpeech());
      final attach = AttachmentViewModel(_FakePicker(), actions);
      final sel = SessionSelection();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ChatViewModel>.value(value: vm),
              ChangeNotifierProvider<VoiceInputViewModel>.value(value: voice),
              ChangeNotifierProvider<AttachmentViewModel>.value(value: attach),
              ChangeNotifierProvider<Preferences>.value(value: prefs),
              ChangeNotifierProvider<SessionSelection>.value(value: sel),
            ],
            child: const ChatPage(
              initialTitle: 'My Project',
              initialDevice: 'MacBook de Jacob',
              initialOnline: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // Line 2 = device (from initialDevice, even with no PeerRecord loaded).
      expect(find.text('MacBook de Jacob'), findsOneWidget);
      // Line 1 = room title (from initialTitle) — distinct from the device, so
      // we know the subtitle isn't just echoing the title fallback.
      expect(find.text('My Project'), findsOneWidget);

      // The info button renders immediately — even with no PeerRecord loaded
      // (activePeer == null here) — so it never pops in and shifts the AppBar.
      expect(find.byIcon(LucideIcons.info), findsOneWidget);

      // Status dot uses initialOnline before the runtime resolves → shows
      // "online" immediately instead of flashing offline/reconnecting.
      expect(find.text('online'), findsOneWidget);
      expect(tester.widget<Text>(find.text('online')).style?.fontSize, 12);
      expect(
        tester.widget<Text>(find.text('MacBook de Jacob')).style?.fontSize,
        12,
      );

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(234, 842);
      await tester.pump();
      expect(find.byKey(const Key('chat-header-compact')), findsOneWidget);
      expect(find.byKey(const Key('chat-status-compact')), findsOneWidget);
      expect(
        find.byKey(const Key('chat-status-priority-label')),
        findsOneWidget,
        reason: 'narrow headers show only the highest-priority status label',
      );
      expect(
        tester.widget<Text>(find.text('My Project')).maxLines,
        1,
        reason: 'the compact room title must stay on one ellipsized line',
      );
      expect(
        find.text('MacBook de Jacob'),
        findsNothing,
        reason: 'the compact header gives its second line to status',
      );
      expect(tester.takeException(), isNull);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        vm.resumeRefreshes,
        1,
        reason: 'the mounted route owns resume hydration',
      );

      // Unmount + dispose in-body (the framework's pending-timer check runs
      // before addTearDown; conn's watchdog must be cancelled here).
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      attach.dispose();
      voice.dispose();
      actions.dispose();
      sync.dispose();
      sel.dispose();
      conn.dispose();
    },
  );
}

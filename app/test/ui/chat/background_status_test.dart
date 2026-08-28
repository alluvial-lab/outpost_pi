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
import 'package:app/ui/chat/attachment/viewmodels/attachment_viewmodel.dart';
import 'package:app/ui/chat/chat_page.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/chat/voice/viewmodels/voice_input_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

class _FakeChannel implements IChannel {
  final _messages = StreamController<ServerMessage>.broadcast();

  @override
  Stream<ServerMessage> get serverMessages => _messages.stream;

  @override
  Future<void> send(ClientMessage msg) async {}

  @override
  Future<void> close() => _messages.close();
}

class _FakeStorage extends PairingStorage {
  @override
  Future<List<PeerRecord>> listPeers() async => const [];

  @override
  Future<PeerRecord?> loadPeer(String epk) async => null;
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSpeech implements SpeechService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePicker implements IImagePickerService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestChatViewModel extends ChatViewModel {
  _TestChatViewModel(
    super.read,
    super.sync,
    super.conn,
    super.prefs,
    super.storage,
  );

  void showStatus(ChatStatusProjection status) {
    emit(ChatReady(messages: const [], status: status));
  }
}

void main() {
  late Directory directory;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync(
      'outpost-background-status-',
    );
    await LocalBoxes.initForTest(directory.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets('background status is rendered with turn precedence', (
    tester,
  ) async {
    final connection = ConnectionManager(
      factory: (_, _) async => _FakeChannel(),
      storage: _FakeStorage(),
    );
    final boxes = LocalBoxes();
    final sync = SyncService(connection, boxes);
    final preferences = Preferences(_FakeSecureStorage());
    final storage = _FakeStorage();
    final viewModel = _TestChatViewModel(
      SessionReadRepository(boxes),
      sync,
      connection,
      preferences,
      storage,
    );
    final actions = ActionsRepository(connection);
    final voice = VoiceInputViewModel(_FakeSpeech());
    final attachment = AttachmentViewModel(_FakePicker(), actions);

    const onlineIdle = ChatStatusProjection(
      transport: ChatTransportOnline(roomId: 'main'),
      turn: AppTurnProjection.idle,
      steering: NoSteering(),
      background: true,
    );
    const onlineWorking = ChatStatusProjection(
      transport: ChatTransportOnline(roomId: 'main'),
      turn: AppTurnProjection(status: AppTurnStatus.working),
      steering: NoSteering(),
      background: true,
    );
    const onlineDone = ChatStatusProjection(
      transport: ChatTransportOnline(roomId: 'main'),
      turn: AppTurnProjection(status: AppTurnStatus.done),
      steering: NoSteering(),
      background: true,
    );
    const onlineStale = ChatStatusProjection(
      transport: ChatTransportOnline(roomId: 'main'),
      turn: AppTurnProjection(status: AppTurnStatus.stale),
      steering: NoSteering(),
      background: true,
    );
    const onlineWithoutBackground = ChatStatusProjection(
      transport: ChatTransportOnline(roomId: 'main'),
      turn: AppTurnProjection.idle,
      steering: NoSteering(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<ChatViewModel>.value(value: viewModel),
            ChangeNotifierProvider<VoiceInputViewModel>.value(value: voice),
            ChangeNotifierProvider<AttachmentViewModel>.value(
              value: attachment,
            ),
            ChangeNotifierProvider<Preferences>.value(value: preferences),
          ],
          child: const ChatPage(initialOnline: true),
        ),
      ),
    );
    await tester.pump();

    viewModel.showStatus(onlineIdle);
    await tester.pump();
    expect(find.text('orchestrating…'), findsOneWidget);

    viewModel.showStatus(onlineWorking);
    await tester.pump();
    expect(find.text('working…'), findsOneWidget);
    expect(find.text('orchestrating…'), findsNothing);

    for (final terminalStatus in [onlineDone, onlineStale]) {
      viewModel.showStatus(terminalStatus);
      await tester.pump();
      expect(find.text('orchestrating…'), findsOneWidget);
      expect(find.text(terminalStatus == onlineDone ? 'done' : 'stale'), findsNothing);
    }

    viewModel.showStatus(onlineWithoutBackground);
    await tester.pump();
    expect(find.text('online'), findsOneWidget);
    expect(find.text('orchestrating…'), findsNothing);

    viewModel.dispose();
    sync.dispose();
    connection.dispose();
  });
}

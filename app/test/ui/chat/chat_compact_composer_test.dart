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
import 'package:app/ui/chat/widgets/input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

class _FakeChannel implements IChannel {
  final _controller = StreamController<ServerMessage>.broadcast();

  @override
  Stream<ServerMessage> get serverMessages => _controller.stream;

  @override
  Future<void> send(ClientMessage msg) async {}

  @override
  Future<void> close() => _controller.close();
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

class _StableChatViewModel extends ChatViewModel {
  _StableChatViewModel(
    super.read,
    super.sync,
    super.conn,
    super.prefs,
    super.storage,
  );

  @override
  Future<void> initialize() async {}

  void seedTranscript() {
    emit(
      const ChatReady(
        messages: [UserMsg(id: 'message-1', text: 'Keep the body scrollable')],
      ),
    );
  }
}

class _ChatHarness {
  _ChatHarness._({
    required this.connection,
    required this.sync,
    required this.actions,
    required this.chat,
    required this.voice,
    required this.attachment,
    required this.preferences,
    required this.selection,
  });

  factory _ChatHarness.create() {
    final storage = _FakeStorage();
    final connection = ConnectionManager(
      factory: (_, _) async => _FakeChannel(),
      storage: storage,
    );
    final boxes = LocalBoxes();
    final sync = SyncService(connection, boxes);
    final preferences = Preferences(_FakeSecureStorage());
    final actions = ActionsRepository(connection);
    final chat = _StableChatViewModel(
      SessionReadRepository(boxes),
      sync,
      connection,
      preferences,
      storage,
    )..seedTranscript();
    return _ChatHarness._(
      connection: connection,
      sync: sync,
      actions: actions,
      chat: chat,
      voice: VoiceInputViewModel(_FakeSpeech()),
      attachment: AttachmentViewModel(_FakePicker(), actions),
      preferences: preferences,
      selection: SessionSelection(),
    );
  }

  final ConnectionManager connection;
  final SyncService sync;
  final ActionsRepository actions;
  final ChatViewModel chat;
  final VoiceInputViewModel voice;
  final AttachmentViewModel attachment;
  final Preferences preferences;
  final SessionSelection selection;

  Widget build() => MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatViewModel>.value(value: chat),
        ChangeNotifierProvider<VoiceInputViewModel>.value(value: voice),
        ChangeNotifierProvider<AttachmentViewModel>.value(value: attachment),
        ChangeNotifierProvider<Preferences>.value(value: preferences),
        ChangeNotifierProvider<SessionSelection>.value(value: selection),
      ],
      child: const ChatPage(),
    ),
  );

  void dispose() {
    chat.dispose();
    attachment.dispose();
    voice.dispose();
    actions.dispose();
    sync.dispose();
    selection.dispose();
    connection.dispose();
  }
}

void main() {
  late Directory directory;

  setUpAll(() async {
    directory = Directory.systemTemp.createTempSync('outpost_compact_chat_');
    await LocalBoxes.initForTest(directory.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'keyboard inset ramp enters compact once and remains compact when settled',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 420);
      final harness = _ChatHarness.create();

      await tester.pumpWidget(harness.build());
      await tester.pump();

      int maxLines() =>
          tester.widget<TextField>(find.byType(TextField)).maxLines!;

      final observedMaxLines = <int>[maxLines()];
      for (final inset in <double>[130, 145, 135, 160, 280]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump();
        observedMaxLines.add(maxLines());
      }

      expect(
        observedMaxLines,
        <int>[6, 6, 1, 1, 1, 1],
        reason:
            'threshold jitter during the IME ramp must not bounce the '
            'composer back to standard before the settled 280dp inset',
      );

      await tester.pumpWidget(const SizedBox());
      harness.dispose();
    },
  );

  testWidgets(
    'folded keyboard cycle restores the full chat height without a residual inset',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 797);
      final harness = _ChatHarness.create();

      await tester.pumpWidget(harness.build());
      await tester.pump();

      final chat = find.byType(ChatPage);
      final composer = find.byKey(const Key('input-bar-height'));
      final field = find.byType(TextField);
      final initialComposerHeight = tester.getSize(composer).height;

      await tester.tap(field);
      await tester.pump();
      for (final inset in <double>[80, 160, 240, 280, 240, 160, 80, 0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump();
        expect(
          MediaQuery.viewInsetsOf(tester.element(chat)).bottom,
          inset,
          reason: 'the chat route must receive every animated IME inset',
        );
        expect(
          tester.getBottomLeft(composer).dy,
          797 - inset,
          reason: 'the Scaffold viewport must track the current IME inset',
        );
      }

      expect(MediaQuery.viewInsetsOf(tester.element(chat)).bottom, 0);
      expect(tester.getSize(chat), const Size(411, 797));
      expect(tester.getBottomLeft(composer).dy, 797);
      expect(tester.getSize(composer).height, initialComposerHeight);
      expect(tester.widget<TextField>(field).maxLines, 6);

      await tester.pumpWidget(const SizedBox());
      harness.dispose();
    },
  );

  testWidgets('focused editable identity survives legitimate compact flips', (
    tester,
  ) async {
    Widget buildBar({required bool compact}) => MaterialApp(
      home: Scaffold(
        body: InputBar(compactHeight: compact, onSend: (_) {}),
      ),
    );

    await tester.pumpWidget(buildBar(compact: false));
    final fieldFinder = find.byType(TextField);
    await tester.tap(fieldFinder);
    await tester.pump();

    final standardField = tester.widget<TextField>(fieldFinder);
    final focusNode = standardField.focusNode!;
    final controller = standardField.controller!;
    final editableElement = tester.element(find.byType(EditableText));
    expect(focusNode.hasFocus, isTrue);
    expect(focusNode.context, isNotNull);
    expect(standardField.maxLines, 6);

    await tester.pumpWidget(buildBar(compact: true));
    final compactField = tester.widget<TextField>(fieldFinder);
    expect(compactField.maxLines, 1);
    expect(identical(compactField.focusNode, focusNode), isTrue);
    expect(identical(compactField.controller, controller), isTrue);
    expect(
      identical(tester.element(find.byType(EditableText)), editableElement),
      isTrue,
    );
    expect(focusNode.hasFocus, isTrue);
    expect(focusNode.context, isNotNull);

    await tester.pumpWidget(buildBar(compact: false));
    final restoredField = tester.widget<TextField>(fieldFinder);
    expect(restoredField.maxLines, 6);
    expect(identical(restoredField.focusNode, focusNode), isTrue);
    expect(identical(restoredField.controller, controller), isTrue);
    expect(
      identical(tester.element(find.byType(EditableText)), editableElement),
      isTrue,
    );
    expect(focusNode.hasFocus, isTrue);
    expect(focusNode.context, isNotNull);
  });
}

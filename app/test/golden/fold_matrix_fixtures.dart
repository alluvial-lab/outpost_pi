import 'dart:async';
import 'dart:typed_data';

import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/images/image_picker_service.dart';
import 'package:app/data/local/boxes.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/voice/speech_service.dart';
import 'package:app/domain/contracts/dismissed_update_store.dart';
import 'package:app/domain/contracts/update_checker.dart';
import 'package:app/domain/contracts/url_opener.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/domain/entities/update_info.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/chat/attachment/viewmodels/attachment_viewmodel.dart';
import 'package:app/ui/chat/chat_page.dart';
import 'package:app/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/chat/voice/viewmodels/voice_input_viewmodel.dart';
import 'package:app/ui/chat/widgets/detail_placeholder.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/home/home_page.dart';
import 'package:app/ui/home/states/home_state.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:app/ui/onboarding/onboarding_page.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';
import 'package:app/ui/onboarding/viewmodels/onboarding_viewmodel.dart';
import 'package:app/ui/pairing/pairing_page.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:app/ui/storage_recovery/transcript_storage_recovery_page.dart';
import 'package:app/ui/sync_required/sync_required_page.dart';
import 'package:app/ui/update/viewmodels/update_banner_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:outpost_pi_identity/outpost_pi_identity.dart';
import 'package:provider/provider.dart';

const foldPeerA = PeerRecord(
  remoteEpk: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  sessionName: 'studio-mac',
  nickname: 'Studio MacBook Pro',
  relayUrl: 'wss://relay.example.test',
  pairedAt: '2026-08-20T08:30:00Z',
  roomId: 'outpost-app',
);

const foldPeerB = PeerRecord(
  remoteEpk: 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
  sessionName: 'build-server',
  nickname: 'Linux Build Workstation',
  relayUrl: 'wss://relay.example.test',
  pairedAt: '2026-08-18T15:10:00Z',
  roomId: 'relay-hardening',
);

const foldRoomsA = <RoomInfo>[
  RoomInfo(
    roomId: 'outpost-app',
    sessionId: 'session-app-20260823',
    startedAt: 1787479200000,
    name: 'outpost_pi mobile fold and split-screen verification',
    cwd: '/home/agent/projects/outpost_pi/app',
    model: 'openai-codex/gpt-5.6-sol',
    thinking: ThinkingLevel.high,
    working: true,
  ),
  RoomInfo(
    roomId: 'site-copy',
    sessionId: 'session-site-20260823',
    startedAt: 1787475600000,
    name: 'site',
    cwd: '/home/agent/projects/outpost_pi/site',
    model: 'kimi-coding/k3',
  ),
  RoomInfo(
    roomId: 'release-notes',
    sessionId: 'session-notes-20260823',
    startedAt: 1787472000000,
    name: 'release-notes-v0.5.2-and-device-installation-guide',
    cwd: '/home/agent/projects/outpost_pi/docs/releases',
    model: 'zai/glm-5.2',
  ),
];

const foldRoomsB = <RoomInfo>[
  RoomInfo(
    roomId: 'relay-hardening',
    sessionId: 'session-relay-20260823',
    startedAt: 1787468400000,
    name: 'relay',
    cwd: '/srv/outpost_pi/relay',
    model: 'openai-codex/gpt-5.6-luna',
  ),
];

final class FoldMemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

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
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class FoldPairingStorage extends PairingStorage {
  FoldPairingStorage() : super(FoldMemorySecureStorage());

  final List<PeerRecord> peers = <PeerRecord>[foldPeerA, foldPeerB];

  @override
  Future<List<PeerRecord>> listPeers() async => List<PeerRecord>.of(peers);

  @override
  Future<PeerRecord?> loadPeer(String epk) async {
    for (final peer in peers) {
      if (peer.remoteEpk == epk) return peer;
    }
    return null;
  }

  @override
  Future<void> savePeer(PeerRecord peer) async {}

  @override
  Future<void> saveRooms(String epk, List<PersistedRoom> rooms) async {}

  @override
  Future<List<PersistedRoom>> loadRooms(String epk) async => const [];
}

final class FoldChannel implements IChannel {
  final StreamController<ServerMessage> _messages =
      StreamController<ServerMessage>.broadcast();

  @override
  Stream<ServerMessage> get serverMessages => _messages.stream;

  @override
  Future<void> send(ClientMessage msg) async {}

  @override
  Future<void> close() => _messages.close();
}

final class FoldHomeViewModel extends HomeViewModel {
  FoldHomeViewModel(super.storage, super.prefs, super.conn);

  final Set<String> liveRooms = <String>{
    'outpost-app',
    'site-copy',
    'relay-hardening',
  };

  @override
  bool get isRelayConnected => true;

  @override
  bool isRoomLive(String epk, String roomId) => liveRooms.contains(roomId);

  @override
  bool isRoomWorking(String epk, String roomId) => roomId == 'outpost-app';

  @override
  List<HomeItem> get visibleItems {
    final current = state;
    return current is HomeList ? current.items() : const <HomeItem>[];
  }

  @override
  ({int all, int online, int offline}) get counts =>
      (all: 4, online: 3, offline: 1);
}

final class FoldSpeechService implements SpeechService {
  @override
  Stream<double> get soundLevel => const Stream<double>.empty();

  @override
  Future<SpeechAvailability> init({String? preferredLocaleId}) async =>
      const SpeechReady('en_US');

  @override
  Future<void> start({
    required String localeId,
    required Duration maxDuration,
  }) async {}

  @override
  Future<String> stop() async => '';

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}
}

final class FoldImagePickerService implements IImagePickerService {
  @override
  Future<PickedImage?> pickFromCamera() async => null;

  @override
  Future<PickedImage?> pickFromGallery() async => null;
}

final class FoldActionsRepository implements IActionsRepository {
  const FoldActionsRepository();

  @override
  ActiveRoomMeta get activeRoomMeta => const ActiveRoomMeta(
    peerEpk: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    roomId: 'outpost-app',
    model: 'openai-codex/gpt-5.6-sol',
    thinking: ThinkingLevel.high,
  );

  @override
  Stream<ActiveRoomMeta> get activeRoomMetaStream =>
      const Stream<ActiveRoomMeta>.empty();

  @override
  Future<void> compact() async {}

  @override
  Future<void> newSession() async {}

  @override
  Future<void> setModel(String provider, String modelId) async {}

  @override
  Future<void> setThinking(ThinkingLevel level) async {}

  @override
  Future<ModelsCatalogue> listModels({bool forceRefresh = false}) async =>
      const ModelsCatalogue(models: <WireModel>[], current: null);

  @override
  void dispose() {}
}

final class FoldChatViewModel extends ChatViewModel {
  FoldChatViewModel(
    super.read,
    super.sync,
    super.conn,
    super.prefs,
    super.storage,
  ) {
    emit(
      const ChatReady(
        messages: <ChatMessage>[
          UserMsg(
            id: 'user-1',
            text:
                'Audit every real mobile surface at Pixel Fold and split-screen sizes. Keep the evidence readable and do not fix issues.',
          ),
          AssistantMsg(
            id: 'assistant-1',
            text:
                'I am rendering the production widgets at each requested logical window. The matrix covers folded portrait and landscape, unfolded portrait and landscape, and three split-screen widths. Long prose is included here so reviewers can see whether assistant output has a comfortable reading measure on a wide detail pane rather than stretching from edge to edge across the entire available chat width.',
          ),
          UserMsg(id: 'user-2', text: 'Show the host-side command too.'),
          AssistantMsg(
            id: 'assistant-2',
            text:
                'Use the repository command:\n\n```bash\nflutter test test/golden/ --exclude-tags e2e\n```\n\nThe render farm writes PNG evidence without changing production behavior.',
          ),
        ],
        streaming: StreamingMessage(
          inReplyTo: 'user-2',
          buffer: 'Rendering the remaining Fold geometries…',
        ),
        status: ChatStatusProjection(
          transport: ChatTransportOnline(roomId: 'outpost-app'),
          turn: AppTurnProjection(
            status: AppTurnStatus.streaming,
            turnId: 'turn-fold-audit',
            replyTo: 'user-2',
          ),
          steering: NoSteering(),
        ),
      ),
    );
  }

  @override
  Future<void> initialize() async {}

  @override
  PeerRecord? get activePeer => foldPeerA;

  @override
  RoomInfo? get activeRoom => foldRoomsA.first;

  @override
  bool get connectionResolved => true;

  @override
  Future<void> refreshOnResume() async {}

  @override
  Future<void> clearActiveSession() async {}

  @override
  Future<void> sendMessage(String text, {MessageImage? image}) async {}

  @override
  Future<void> cancel(String targetId) async {}

  @override
  Future<void> approveTool(String toolCallId, ApproveDecision decision) async {}
}

final class FoldUpdateChecker implements UpdateChecker {
  const FoldUpdateChecker();

  @override
  Future<UpdateInfo?> fetchLatest() async => null;
}

final class FoldDismissedUpdateStore implements DismissedUpdateStore {
  const FoldDismissedUpdateStore();

  @override
  Future<String?> dismissedVersion() async => null;

  @override
  Future<void> dismiss(String version) async {}
}

final class FoldUrlOpener implements UrlOpener {
  const FoldUrlOpener();

  @override
  Future<bool> open(String url) async => true;
}

final class FoldPairingViewModel extends PairingViewModel {
  FoldPairingViewModel(
    super.storage,
    super.transportFactory,
    super.conn,
    super.prefs,
    super.ownerBridge,
  ) {
    emit(const PairingScanning());
  }
}

final class FoldOnboardingViewModel extends OnboardingViewModel {
  FoldOnboardingViewModel(super.prefs);

  void show(OnboardingStep step) {
    emit(
      OnboardingInProgress(
        step: step,
        customRelayUrl: 'wss://relay.outpost.example',
      ),
    );
  }
}

final class FoldMatrixFixture {
  FoldMatrixFixture._({
    required this.storage,
    required this.preferences,
    required this.connection,
    required this.home,
    required this.chat,
    required this.sync,
    required this.voice,
    required this.attachment,
    required this.actions,
    required this.update,
    required this.selection,
    required this.shellLayout,
    required this.ownerBridge,
    required this.pairing,
    required this.onboarding,
  });

  final FoldPairingStorage storage;
  final Preferences preferences;
  final ConnectionManager connection;
  final FoldHomeViewModel home;
  final FoldChatViewModel chat;
  final SyncService sync;
  final VoiceInputViewModel voice;
  final AttachmentViewModel attachment;
  final FoldActionsRepository actions;
  final UpdateBannerViewModel update;
  final SessionSelection selection;
  final ShellLayout shellLayout;
  final OwnerIdentityBridge ownerBridge;
  final FoldPairingViewModel pairing;
  final FoldOnboardingViewModel onboarding;

  static Future<FoldMatrixFixture> create() async {
    final storage = FoldPairingStorage();
    final secureStorage = FoldMemorySecureStorage();
    final preferences = Preferences(secureStorage);
    await preferences.setSelectedRoom(
      epk: foldPeerA.remoteEpk,
      roomId: 'outpost-app',
    );
    await preferences.setRelayUrl('wss://relay.outpost.example');

    final connection = ConnectionManager(
      factory: (_, _) async => FoldChannel(),
      storage: storage,
    );
    final home = FoldHomeViewModel(storage, preferences, connection);
    await Future<void>.delayed(Duration.zero);
    home.emit(
      const HomeList(
        peers: <PeerRecord>[foldPeerA, foldPeerB],
        roomsByPeer: <String, List<RoomInfo>>{
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA': foldRoomsA,
          'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB': foldRoomsB,
        },
        filter: HomeFilter.all,
      ),
    );

    final boxes = LocalBoxes();
    final sync = SyncService(connection, boxes);
    final chat = FoldChatViewModel(
      SessionReadRepository(boxes),
      sync,
      connection,
      preferences,
      storage,
    );
    final actions = const FoldActionsRepository();
    final voice = VoiceInputViewModel(FoldSpeechService());
    final attachment = AttachmentViewModel(FoldImagePickerService(), actions);
    final update = UpdateBannerViewModel(
      const FoldUpdateChecker(),
      const FoldDismissedUpdateStore(),
      const FoldUrlOpener(),
      currentVersion: '0.5.2',
      enabled: false,
    );
    final selection = SessionSelection()
      ..select(
        const RemoteSessionRef(
          peerEpk: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          roomId: 'outpost-app',
          sessionId: 'session-app-20260823',
        ),
        foldRoomsA.first.name!,
        foldPeerA.nickname!,
        true,
      );
    final shellLayout = ShellLayout();
    final ownerBridge = OwnerIdentityBridge(
      InMemoryOwnerIdentityStore(
        initial: OwnerIdentity(ownerPk: Uint8List(32), ownerSk: Uint8List(32)),
      ),
      storage,
    );
    final pairing = FoldPairingViewModel(
      storage,
      (_, _) async => throw StateError('unused golden pairing transport'),
      connection,
      preferences,
      ownerBridge,
    );
    final onboarding = FoldOnboardingViewModel(preferences);

    return FoldMatrixFixture._(
      storage: storage,
      preferences: preferences,
      connection: connection,
      home: home,
      chat: chat,
      sync: sync,
      voice: voice,
      attachment: attachment,
      actions: actions,
      update: update,
      selection: selection,
      shellLayout: shellLayout,
      ownerBridge: ownerBridge,
      pairing: pairing,
      onboarding: onboarding,
    );
  }

  Widget providers({required Widget child}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<HomeViewModel>.value(value: home),
        ChangeNotifierProvider<ChatViewModel>.value(value: chat),
        ChangeNotifierProvider<VoiceInputViewModel>.value(value: voice),
        ChangeNotifierProvider<AttachmentViewModel>.value(value: attachment),
        ChangeNotifierProvider<UpdateBannerViewModel>.value(value: update),
        ChangeNotifierProvider<Preferences>.value(value: preferences),
        ChangeNotifierProvider<SessionSelection>.value(value: selection),
        ChangeNotifierProvider<ShellLayout>.value(value: shellLayout),
        ChangeNotifierProvider<PairingViewModel>.value(value: pairing),
        ChangeNotifierProvider<OnboardingViewModel>.value(value: onboarding),
      ],
      child: child,
    );
  }

  Widget homeSurface() => providers(child: const HomePage());

  Widget noPeerSurface() {
    home.emit(const HomeNoPeer());
    return providers(child: const HomePage());
  }

  Widget pairingScanningSurface() => providers(child: const PairingPage());

  Widget chatSurface({bool showBack = true}) => providers(
    child: ChatPage(
      initialTitle: foldRoomsA.first.name,
      initialDevice: foldPeerA.nickname,
      initialOnline: true,
      showBack: showBack,
    ),
  );

  Widget shellSurface({bool detailSelected = true}) {
    if (detailSelected) {
      selection.select(
        const RemoteSessionRef(
          peerEpk: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          roomId: 'outpost-app',
          sessionId: 'session-app-20260823',
        ),
        foldRoomsA.first.name!,
        foldPeerA.nickname!,
        true,
      );
    } else {
      selection.clear();
    }
    return providers(
      child: FoldProductionShellMirror(detailSelected: detailSelected),
    );
  }

  Widget onboardingSurface(OnboardingStep step) {
    onboarding.show(step);
    return providers(child: const OnboardingPage());
  }

  Widget syncRequiredSurface() => providers(child: const SyncRequiredPage());

  Widget storageRecoverySurface() => providers(
    child: TranscriptStorageRecoveryPage(
      onRetry: () async {},
      onDiscard: () async {},
    ),
  );

  Future<void> dispose() async {
    onboarding.dispose();
    pairing.dispose();
    ownerBridge.dispose();
    update.dispose();
    attachment.dispose();
    voice.dispose();
    chat.dispose();
    home.dispose();
    sync.dispose();
    connection.dispose();
    selection.dispose();
    shellLayout.dispose();
    preferences.dispose();
    storage.dispose();
  }
}

/// Mirror the production `navigatorContainerBuilder` without booting GoRouter.
///
/// The pane composition, fixed 360dp master, divider, Home-only keyboard
/// isolation, and divider-facing padding match `lib/routing/app_router.dart`.
final class FoldProductionShellMirror extends StatelessWidget {
  const FoldProductionShellMirror({super.key, required this.detailSelected});

  final bool detailSelected;

  @override
  Widget build(BuildContext context) {
    if (!canUseTwoPaneLayout(context)) return const HomePage();
    return Row(
      children: <Widget>[
        const SizedBox(
          width: kMasterPaneWidth,
          child: MasterPaneHomeSurface(
            isolateKeyboard: true,
            child: HomePage(),
          ),
        ),
        VerticalDivider(
          width: kPaneDividerWidth,
          thickness: kPaneDividerWidth,
          color: context.colors.borderStrong,
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: true,
            child: detailSelected
                ? ChatPage(
                    initialTitle: foldRoomsA.first.name,
                    initialDevice: foldPeerA.nickname,
                    initialOnline: true,
                    showBack: false,
                  )
                : const DetailPlaceholder(),
          ),
        ),
      ],
    );
  }
}

QuickActionsViewModel buildFoldQuickActionsViewModel() =>
    QuickActionsViewModel(const FoldActionsRepository());

import 'dart:async';
import 'dart:io' show Platform;

import 'package:app/config/utils/injector.dart';
import 'package:app/data/actions/actions_repository.dart';
import 'package:app/data/debug/debug_capture_uploader.dart';
import 'package:app/data/debug/debug_log_impl.dart';
import 'package:app/data/mesh/mesh_client.dart';
import 'package:app/data/mesh/mesh_sync_service.dart';
import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/transcript_event_store_hive.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/repositories/home_read_repository.dart';
import 'package:app/data/repositories/session_read_repository.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/channel.dart'; // IChannel
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/identity/device_id.dart';
import 'package:app/data/images/image_picker_service.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:app/data/update/secure_dismissed_update_store.dart';
import 'package:app/data/update/update_checker_impl.dart';
import 'package:app/data/update/url_launcher_opener.dart';
import 'package:app/data/voice/speech_service.dart';
import 'package:app/domain/contracts/debug_capture_upload.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/domain/contracts/dismissed_update_store.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/contracts/update_checker.dart';
import 'package:app/domain/contracts/url_opener.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/qr_scanner.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/chat/attachment/viewmodels/attachment_viewmodel.dart';
import 'package:app/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/chat/voice/viewmodels/voice_input_viewmodel.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:app/ui/onboarding/viewmodels/onboarding_viewmodel.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:app/ui/update/viewmodels/update_banner_viewmodel.dart';
import 'package:cryptography/cryptography.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:outpost_pi_identity/outpost_pi_identity.dart';

final _injector = CustomInjector();

/// Direct injector access — only for bootstrap, tests, and deep-link handlers.
CustomInjector get injector => _injector;

/// Register the app's dependency graph before any route or service resolves it.
///
/// Opens prerequisites first, then binds lifecycle-owned services and route-local
/// ViewModel factories; [disposeDependencies] owns teardown of managed bindings.
Future<void> setupDependencies() async {
  // Infrastructure singletons
  _injector.addInstance<PairingStorage>(PairingStorage());

  final prefs = Preferences();
  await prefs.load();
  _injector.addInstance<Preferences>(prefs);

  // Debug ring log — addService is required so disposeDependencies() flushes
  // pending lines through DebugLogImpl.dispose(). Capture is gated by the
  // persisted app-global Preferences.debugLogging toggle; export/clear remain
  // available while capture is off.
  _injector.addService<DebugLog>(
    () => DebugLogImpl(debugEnabled: () => prefs.debugLogging),
  );

  // Plan 31 — local SSOT box facade (boxes already opened + runtime wiped in
  // bootstrap before this runs).
  _injector.addInstance<LocalBoxes>(LocalBoxes());
  // TranscriptEventStore is a persistence port, but it intentionally does not
  // implement the Repository lifecycle marker. Register it as an injector-owned
  // singleton so SyncService can resolve the port without forcing a fake
  // Repository/dispose contract onto the append-only store adapter.
  _injector.addOther<TranscriptEventStore>(
    () => HiveTranscriptEventStore(_injector.get<LocalBoxes>()),
  );

  // Plan 23 — Owner-key sync. The store talks to the native plugin
  // (iCloud Keychain on iOS, Block Store on Android); the bridge sits
  // between it and the rest of the app, owning boot + watch-for-reset.
  final OwnerIdentityStore ownerStore = MethodChannelOwnerIdentityStore();
  _injector.addInstance<OwnerIdentityStore>(ownerStore);
  final ownerBridge = OwnerIdentityBridge(
    ownerStore,
    _injector.get<PairingStorage>(),
  );
  _injector.addInstance<OwnerIdentityBridge>(
    ownerBridge,
    onDispose: (bridge) => bridge.dispose(),
  );

  // Per-install device id for the relay hello frame — lets the relay close
  // prior same-device conns on reconnect (see
  // story-relay-close-same-device-duplicate-auth).
  _injector.addInstance<DeviceId>(DeviceId());

  // Plan 24 — mesh_versions HTTP client + sync service. Base URL is
  // the user-configured relay verbatim (always http(s):// per the
  // post-Wave-2 URL scheme decision — see plan/24-fix-app-url-scheme).
  // No translation needed: the relay's `/mesh` endpoint shares host +
  // port with the WebSocket.
  final meshClient = MeshClient(
    relayResolutionProvider: () => resolveRelayUrl(prefs),
  );
  _injector.addInstance<MeshClient>(meshClient);
  final meshSync = MeshSyncService(
    meshClient,
    ownerBridge,
    _injector.get<PairingStorage>(),
    debugLog: _injector.get<DebugLog>(),
  );
  _injector.addInstance<MeshSyncService>(meshSync);
  _injector.get<PairingStorage>().attachPeerMutationHook(
    meshSync.publishAfterPeerMutation,
  );

  // ConnectionManager — factory function injected manually (function typedefs
  // cannot be resolved by auto_injector via Type.new).
  _injector.addService<ConnectionManager>(
    () => ConnectionManager(
      factory: _productionConnectionFactory,
      storage: _injector.get<PairingStorage>(),
      debugLog: _injector.get<DebugLog>(),
    ),
  );

  // Plan 29 — on-device speech-to-text. Singleton: it owns a broadcast
  // sound-level stream that must survive across chat navigations; the
  // injector disposes it at app teardown. VoiceInputViewModel never
  // disposes it (it only stops/cancels sessions).
  _injector.addService<SpeechService>(() => SpeechToTextService());

  // Plan 30 — image picker + on-device JPEG compression. Stateless, no
  // dispose hook needed.
  _injector.addOther<IImagePickerService>(() => ImagePickerService());

  // Plan 31 — SSOT writer + read-only repos. SyncService is the SINGLE
  // mutator of the message/index/runtime boxes; the read repos only watch.
  _injector.addService<SyncService>(
    () => SyncService(
      _injector.get<ConnectionManager>(),
      _injector.get<LocalBoxes>(),
      transcriptEventStore: _injector.get<TranscriptEventStore>(),
      debugLog: _injector.get<DebugLog>(),
    ),
  );
  _injector.addRepository<SessionReadRepository>(
    () => SessionReadRepository(_injector.get<LocalBoxes>()),
  );
  _injector.addRepository<HomeReadRepository>(
    () => HomeReadRepository(_injector.get<LocalBoxes>()),
  );

  // Repositories
  _injector.addRepository<IActionsRepository>(
    () => ActionsRepository(_injector.get<ConnectionManager>()),
  );
  _injector.addOther<DebugCaptureUploader>(
    () => DebugCaptureUploaderImpl(
      _injector.get<DebugLog>(),
      _injector.get<ConnectionManager>(),
    ),
  );

  // ViewModels
  _injector.addViewModel<ChatViewModel>(
    () => ChatViewModel(
      _injector.get<SessionReadRepository>(),
      _injector.get<SyncService>(),
      _injector.get<ConnectionManager>(),
      _injector.get<Preferences>(),
      _injector.get<PairingStorage>(),
    ),
  );
  _injector.addViewModel<HomeViewModel>(
    () => HomeViewModel(
      _injector.get<PairingStorage>(),
      _injector.get<Preferences>(),
      _injector.get<ConnectionManager>(),
    ),
  );
  _injector.addViewModel<SettingsViewModel>(
    () => SettingsViewModel(
      _injector.get<PairingStorage>(),
      _injector.get<Preferences>(),
      _injector.get<ConnectionManager>(),
      _injector.get<DebugLog>(),
    ),
  );
  _injector.addViewModel<PairingViewModel>(
    () => PairingViewModel(
      _injector.get<PairingStorage>(),
      _productionPairingTransportFactory,
      _injector.get<ConnectionManager>(),
      _injector.get<Preferences>(),
      _injector.get<OwnerIdentityBridge>(),
      debugLog: _injector.get<DebugLog>(),
    ),
  );
  _injector.addViewModel<OnboardingViewModel>(OnboardingViewModel.new);
  _injector.addViewModel<QuickActionsViewModel>(
    () => QuickActionsViewModel(
      _injector.get<IActionsRepository>(),
      _injector.get<DebugCaptureUploader>(),
    ),
  );
  // Plan 29 — voice input. New instance per chat mount; reuses the shared
  // SpeechService singleton (which it stops/cancels but never disposes).
  _injector.addViewModel<VoiceInputViewModel>(
    () => VoiceInputViewModel(_injector.get<SpeechService>()),
  );
  // Plan 30 — image attachment. New instance per chat mount; resolves model
  // vision via the shared ActionsRepository catalogue cache.
  _injector.addViewModel<AttachmentViewModel>(
    () => AttachmentViewModel(
      _injector.get<IImagePickerService>(),
      _injector.get<IActionsRepository>(),
    ),
  );

  // Plan/tablet — app-global UI selection (which session the tablet's
  // detail pane shows + which list tile is highlighted). Starts null so
  // the app opens with no chat pre-selected.
  _injector.addInstance<SessionSelection>(SessionSelection());

  // Plan/tablet — shell layout state (zero-state collapse). Set by Home so
  // the adaptive shell drops the split when there's nothing to list.
  _injector.addInstance<ShellLayout>(ShellLayout());

  // Plan 44 — Android-only in-app update notice. The running version comes
  // from package_info; the manifest fetch + gating live in the ViewModel
  // (silent on iOS via `enabled` and on any fetch failure). Stateless
  // collaborators → addOther (lazy singleton, no dispose hook).
  final packageInfo = await PackageInfo.fromPlatform();
  final appVersion = packageInfo.version;
  _injector.addOther<UpdateChecker>(() => UpdateCheckerImpl());
  _injector.addOther<DismissedUpdateStore>(() => SecureDismissedUpdateStore());
  _injector.addOther<UrlOpener>(() => const UrlLauncherOpener());
  _injector.addViewModel<UpdateBannerViewModel>(
    () => UpdateBannerViewModel(
      _injector.get<UpdateChecker>(),
      _injector.get<DismissedUpdateStore>(),
      _injector.get<UrlOpener>(),
      currentVersion: appVersion,
      enabled: Platform.isAndroid,
    ),
  );

  _injector.commit();
}

// ---------------------------------------------------------------------------
// Production ConnectionFactory — used by ConnectionManager for reconnection.
// Established peers resume with persisted owner-channel keys; reconnect never
// performs a plaintext fallback or a second handshake.
// Plan 23: Owner-sk (synced via iCloud Keychain / Block Store) is the
// challenge-response key. OwnerIdentityBridge.boot() is the router's
// responsibility; by the time this factory runs, the identity is loaded.
// ---------------------------------------------------------------------------

Future<IChannel> _productionConnectionFactory(
  PeerRecord peer,
  CancelToken cancel,
) async {
  final resolution = resolveRelayUrl(_injector.get<Preferences>());
  if (resolution is! ConfiguredRelay) {
    throw const RelayNotConfiguredException();
  }
  final relayUrl = resolution.url;
  // ConnectionManager retries with the peer snapshot that originally opened
  // the channel. Reload here so persisted sequence advances are never reset by
  // a stale in-memory PeerRecord after a transient disconnect.
  final channelPeer = await _injector.get<PairingStorage>().loadPeer(
    peer.remoteEpk,
  );
  if (channelPeer?.channel == null) {
    throw const PeerChannelError(
      'paired peer predates owner-channel protection; re-pair required',
    );
  }
  if (cancel.isCancelled) throw _CancelledError();

  final bridge = injector.get<OwnerIdentityBridge>();
  final ownerKey = await bridge.requireKeyPair();
  if (cancel.isCancelled) throw _CancelledError();

  // Defensive timeout (plan app-state-normalization): without this the
  // WebSocket connect + Ed25519 challenge round-trip can hang
  // indefinitely if the relay is unreachable — ChatViewModel would sit
  // in `ChatConnecting` forever. Throwing here pushes the manager into
  // its retry/backoff path, which is observable as `StatusRetrying` and
  // renders a "reconnecting" banner rather than an empty spinner.
  const wsConnectTimeout = Duration(seconds: 10);
  // `peer.relayUrl` is kept on PeerRecord for legacy QR payloads but is
  // no longer consulted when opening a connection.
  // Construct the transport with the real destination room from the start
  // so post-auth frames are demuxed against the correct room from frame 1 —
  // the relay can push envelopes before any post-connect setActiveRoom call
  // could land, which previously dropped them as `room-mismatch` (see
  // `story-fix-transport-active-room-reestablishment-on-reconnect`).
  final transport =
      await WsTransport.connect(
        relayUrl: relayUrl,
        peerPubkey: channelPeer!.remoteEpk,
        ed25519Key: ownerKey,
        deviceId: await _injector.get<DeviceId>().get(),
        activeRoom: channelPeer.roomId ?? 'main',
        debugLog: _injector.get<DebugLog>(),
      ).timeout(
        wsConnectTimeout,
        onTimeout: () => throw TimeoutException(
          'WS connect to $relayUrl timed out after '
          '${wsConnectTimeout.inSeconds}s',
        ),
      );

  if (cancel.isCancelled) {
    await transport.close();
    throw _CancelledError();
  }

  return SecurePeerChannel(
    transport: transport,
    storage: _injector.get<PairingStorage>(),
    peer: channelPeer,
    debugLog: _injector.get<DebugLog>(),
  );
}

// ---------------------------------------------------------------------------
// Production PairingTransportFactory — used by PairingViewModel for first pair.
// ---------------------------------------------------------------------------

Future<PeerTransport> _productionPairingTransportFactory(
  QrPairPayload qr,
  SimpleKeyPair deviceEd25519,
) async {
  // Plan 14: pairing connects via the GLOBAL relay URL (Preferences),
  // not whatever was embedded in the QR. Mismatch between qr.relayUrl
  // and the user's configured relay is handled upstream by
  // `pair_request_flow.dart` (raises a `relay_mismatch` error that
  // PairingViewModel surfaces as a "trocar relay?" modal).
  //
  // Construct with the QR's room so the pair_request itself is routed
  // correctly AND post-auth frames are demuxed against the right room
  // from frame 1. `performPairing`'s own `setActiveRoom` is now a
  // redundant safety (kept harmless) — see
  // `story-fix-transport-active-room-reestablishment-on-reconnect`.
  final resolution = resolveRelayUrl(_injector.get<Preferences>());
  if (resolution is! ConfiguredRelay) {
    throw const RelayNotConfiguredException();
  }
  return WsTransport.connect(
    relayUrl: resolution.url,
    peerPubkey: qr.epk,
    ed25519Key: deviceEd25519,
    deviceId: await _injector.get<DeviceId>().get(),
    activeRoom: qr.roomId ?? 'main',
    debugLog: _injector.get<DebugLog>(),
  );
}

// ---------------------------------------------------------------------------

class _CancelledError implements Exception {
  const _CancelledError();
}

/// Dispose every injector-owned service and repository during app shutdown.
void disposeDependencies() => _injector.dispose();

/// Bridge auto_injector and Provider with a route-owned ViewModel instance.
///
/// Each mounted provider resolves a fresh ViewModel; Provider disposes it when
/// that route leaves the tree. This prevents screen state from becoming global.
///
/// Creates a `ChangeNotifierProvider` that
/// asks the injector for a fresh `ViewModel<T>` instance on each route mount.
class ViewmodelProvider<T extends ViewModel> extends ChangeNotifierProvider<T> {
  ViewmodelProvider({super.key, super.child})
    : super(create: (_) => _injector.get<T>());

  ViewmodelProvider.value({super.key, required super.value, super.child})
    : super.value();
}

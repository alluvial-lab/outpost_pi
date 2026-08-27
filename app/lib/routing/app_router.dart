import 'dart:async';

import 'package:app/config/dependencies.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/data/local/boxes.dart';
import 'package:app/data/mesh/mesh_sync_service.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/ui/chat/attachment/viewmodels/attachment_viewmodel.dart';
import 'package:app/ui/chat/chat_page.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/chat/voice/viewmodels/voice_input_viewmodel.dart';
import 'package:app/ui/chat/widgets/detail_placeholder.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/home/home_page.dart';
import 'package:app/ui/home/viewmodels/home_viewmodel.dart';
import 'package:app/ui/onboarding/onboarding_page.dart';
import 'package:app/ui/onboarding/viewmodels/onboarding_viewmodel.dart';
import 'package:app/ui/pairing/pairing_page.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:app/ui/settings/settings_page.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:app/ui/sync_required/sync_required_page.dart';
import 'package:app/ui/update/viewmodels/update_banner_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Identify the boot phase whose retryable failure is shown on `/boot`.
enum BootFailureStage { preferences, identity, storage, connection }

/// Carry a safe boot failure without exposing its underlying exception.
final class BootFailure {
  const BootFailure(this.stage, this.message);

  final BootFailureStage stage;
  final String message;
}

/// Own generation-guarded router bootstrap and its retryable failure state.
///
/// The router uses this as `refreshListenable`; tests exercise the same public
/// boundary so boot completion cannot drift from redirect readiness.
class BootState extends ChangeNotifier {
  bool _ready = false;
  bool _hasPeer = false;
  bool _onboarded = false;
  bool _syncAvailable = true;
  bool _identityWasGenerated = false;
  bool _loading = false;
  bool _disposed = false;
  int _generation = 0;
  BootFailure? _failure;

  bool get ready => _ready;
  bool get hasPeer => _hasPeer;
  bool get onboarded => _onboarded;
  bool get syncAvailable => _syncAvailable;
  bool get loading => _loading;
  BootFailure? get failure => _failure;

  /// True when this run is the very first time the Owner key materialised
  /// on this account (the bridge just generated it). Restored identities
  /// — anything coming back from iCloud Keychain / Block Store, including
  /// the "reinstalled the app on the same device" case where the platform
  /// re-hands the previous key — set this to false.
  bool get identityWasGenerated => _identityWasGenerated;

  /// Restore local boot state and settle the initial connection attempt.
  ///
  /// Expected relay failures are projected by [ConnectionManager] as retrying;
  /// exceptions at a boot phase remain owned here and become retryable UI.
  Future<void> load(
    PairingStorage storage,
    ConnectionManager conn,
    Preferences prefs,
    OwnerIdentityBridge ownerBridge,
    MeshSyncService meshSync, {
    void Function()? installWatcherAfterBoot,
    Future<void> Function(bool Function() stillCurrent)?
    cleanPendingOwnerTransition,
  }) async {
    if (_disposed) return;
    final generation = ++_generation;
    _ready = false;
    _failure = null;
    _loading = true;
    _hasPeer = false;
    _onboarded = false;
    _identityWasGenerated = false;
    notifyListeners();

    try {
      await prefs.load();
    } on Object {
      _fail(
        generation,
        BootFailureStage.preferences,
        'Could not load app settings. Try again.',
      );
      return;
    }
    if (!_isCurrent(generation)) return;

    OwnerIdentityBootResult ownerResult;
    try {
      ownerResult = await ownerBridge.boot();
    } on Object {
      _fail(
        generation,
        BootFailureStage.identity,
        'Could not load your synced identity. Try again.',
      );
      return;
    }
    if (!_isCurrent(generation)) return;
    if (ownerResult is OwnerTransitionPending) {
      final cleanup = cleanPendingOwnerTransition;
      if (cleanup == null) {
        _fail(
          generation,
          BootFailureStage.identity,
          'Could not resume the Owner transition. Try again.',
        );
        return;
      }
      try {
        await cleanup(() => _isCurrent(generation));
        if (!_isCurrent(generation)) return;
        await ownerBridge.completePendingTransition(ownerResult.identity);
      } on Object {
        _fail(
          generation,
          BootFailureStage.storage,
          'Could not complete the Owner transition. Try again.',
        );
        return;
      }
      if (!_isCurrent(generation)) return;
      ownerResult = IdentityReady(ownerResult.identity, generated: false);
    }
    if (ownerResult is SyncUnavailableResult) {
      _syncAvailable = false;
      _loading = false;
      _ready = true;
      notifyListeners();
      return;
    }
    _syncAvailable = true;
    _identityWasGenerated =
        ownerResult is IdentityReady && ownerResult.generated;

    List<PeerRecord> peers;
    try {
      // A false pull result means relay-unavailable local-cache fallback. Only
      // an unexpected thrown storage/crypto failure blocks boot.
      await meshSync.pullOnDemand();
      if (!_isCurrent(generation)) return;
      peers = await storage.listPeers();
      if (!_isCurrent(generation)) return;
      _hasPeer = peers.isNotEmpty;
      if (_hasPeer && !prefs.onboardingCompleted) {
        await prefs.setOnboardingCompleted(true);
        if (!_isCurrent(generation)) return;
      }
      _onboarded = prefs.onboardingCompleted;

      if (_hasPeer) {
        var selected = prefs.selectedPeerEpk;
        if (selected == null ||
            !peers.any((peer) => peer.remoteEpk == selected)) {
          selected = peers.first.remoteEpk;
          await prefs.setSelectedPeerEpk(selected);
          if (!_isCurrent(generation)) return;
        }

        try {
          await conn.boot(preferredEpk: selected);
        } on Object {
          _fail(
            generation,
            BootFailureStage.connection,
            'Could not start the connection. Try again.',
          );
          return;
        }
        if (!_isCurrent(generation)) return;
      }
    } on Object {
      _fail(
        generation,
        BootFailureStage.storage,
        'Could not restore paired devices. Try again.',
      );
      return;
    }

    try {
      if (!_isCurrent(generation)) return;
      installWatcherAfterBoot?.call();
    } on Object {
      _fail(
        generation,
        BootFailureStage.identity,
        'Could not watch your synced identity. Try again.',
      );
      return;
    }
    if (!_isCurrent(generation)) return;
    _loading = false;
    _ready = true;
    notifyListeners();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _fail(int generation, BootFailureStage stage, String message) {
    if (!_isCurrent(generation)) return;
    _loading = false;
    _ready = false;
    _failure = BootFailure(stage, message);
    notifyListeners();
  }

  /// Project a failed Owner-key reset without leaking callback errors.
  void failOwnerReset(int generation) {
    _fail(
      generation,
      BootFailureStage.connection,
      'Could not reset the previous connection. Try again.',
    );
  }

  /// Project a latched transcript-wipe recovery failure during boot retry.
  void failStorageRecovery(int generation) {
    _fail(
      generation,
      BootFailureStage.storage,
      'Could not restore local storage. Try again.',
    );
  }

  /// Return whether [generation] still owns boot continuation side effects.
  bool isCurrentGeneration(int generation) => _isCurrent(generation);

  /// Invalidate in-flight work before retry or Owner-key replacement.
  ///
  /// Returns the new generation token, or `null` after disposal.
  int? invalidate() {
    if (_disposed) return null;
    _generation++;
    _ready = false;
    _loading = false;
    _failure = null;
    _hasPeer = false;
    _onboarded = false;
    notifyListeners();
    return _generation;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

/// Own the router and the boot state/listeners created alongside it.
///
/// The app root must dispose this owner before disposing injected services so
/// no boot or Owner-reset continuation can outlive the application surface.
final class AppRouterOwner {
  AppRouterOwner({
    required this.router,
    required this.bootState,
    required VoidCallback retryBoot,
    required VoidCallback stopPolling,
  }) : _retryBoot = retryBoot,
       _stopPolling = stopPolling;

  final GoRouter router;
  final BootState bootState;
  final VoidCallback _retryBoot;
  final VoidCallback _stopPolling;
  bool _disposed = false;

  /// Start a fresh generation-guarded boot run.
  void retryBoot() {
    if (_disposed) return;
    _retryBoot();
  }

  /// Tear down router listeners, boot work, and router-owned mesh polling.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    router.dispose();
    bootState.dispose();
    _stopPolling();
  }
}

/// Build the app router together with its explicitly owned boot lifecycle.
AppRouterOwner buildRouter(
  PairingStorage storage,
  ConnectionManager conn,
  Preferences prefs,
  OwnerIdentityBridge ownerBridge,
  MeshSyncService meshSync,
) {
  final boot = BootState();

  // The marker is written by OwnerIdentityBridge before this callback runs.
  // Keep the cleanup and commit separate: currentOwnerPk stays inaccessible
  // until pairing state, the live connection, and transcripts are all gone.
  Future<void> cleanPendingOwnerTransition(bool Function() stillCurrent) async {
    await storage.wipeAll();
    if (!stillCurrent()) return;
    await conn.disconnect();
    if (!stillCurrent()) return;
    await LocalBoxes.wipeTranscriptsForOwnerTransition();
    if (!stillCurrent()) return;
    meshSync.resetVersionWatermark();
  }

  var watcherInstalled = false;
  late final void Function() installWatcher;
  Future<void> loadBoot() => boot.load(
    storage,
    conn,
    prefs,
    ownerBridge,
    meshSync,
    installWatcherAfterBoot: installWatcher,
    cleanPendingOwnerTransition: cleanPendingOwnerTransition,
  );

  installWatcher = () {
    if (watcherInstalled) return;
    ownerBridge.startWatching(
      onTransition: (incoming) async {
        final resetGeneration = boot.invalidate();
        if (resetGeneration == null) return;
        try {
          await cleanPendingOwnerTransition(
            () => boot.isCurrentGeneration(resetGeneration),
          );
          if (!boot.isCurrentGeneration(resetGeneration)) return;
          await ownerBridge.completePendingTransition(incoming);
          if (!boot.isCurrentGeneration(resetGeneration)) return;
          await loadBoot();
        } on Object {
          boot.failOwnerReset(resetGeneration);
          rethrow;
        }
      },
    );
    watcherInstalled = true;
  };

  void retryBoot() {
    final retryGeneration = boot.invalidate();
    if (retryGeneration == null) return;
    unawaited(() async {
      try {
        await LocalBoxes.convergePendingOwnerTransitionWipe();
      } on Object {
        boot.failStorageRecovery(retryGeneration);
        return;
      }
      if (!boot.isCurrentGeneration(retryGeneration)) return;
      await loadBoot();
    }());
  }

  unawaited(loadBoot());

  // Plan 24 — start foreground polling. The router doesn't have
  // direct access to AppLifecycleState; main.dart wires
  // [MeshSyncService.startPolling/stopPolling] to the lifecycle so
  // this initial start covers the "app launched in foreground" case.
  meshSync.startPolling();

  final router = GoRouter(
    initialLocation: '/boot',
    refreshListenable: boot,
    redirect: (context, state) {
      if (boot.failure != null || !boot.ready) {
        return state.uri.path == '/boot' ? null : '/boot';
      }
      // Sync-required gate is sticky until the user toggles iCloud /
      // Backup on and taps "Check again". Don't redirect away from
      // /sync-required while the bridge still reports unavailable.
      if (!boot.syncAvailable) {
        return state.uri.path == '/sync-required' ? null : '/sync-required';
      }
      // Onboarding stepper only runs on a truly fresh install — when
      // the Owner key was generated this run AND there is no
      // membership to inherit. Restored identities (iCloud Keychain /
      // Block Store handed us back the key, including the
      // "reinstalled on the same device" case) skip straight to home,
      // even if peers are empty. Home has a first-pair empty state
      // that covers that case more cleanly than re-running the welcome
      // wizard a second time.
      final shouldOnboard = boot.identityWasGenerated && !boot.hasPeer;
      final target = shouldOnboard ? '/onboarding' : '/home';
      if (state.uri.path == '/sync-required' || state.uri.path == '/boot') {
        return target;
      }
      return null;
    },
    routes: [
      // Splash while boot.load() is in flight; phase failures remain here.
      GoRoute(
        path: '/boot',
        builder: (ctx, st) => _BootSplash(state: boot, onRetry: retryBoot),
      ),

      // Plan 23 — first-launch gate when iCloud Keychain / Google
      // Backup is off. Sticky route: redirect keeps the user here
      // until the bridge reports sync available.
      GoRoute(
        path: '/sync-required',
        builder: (ctx, st) => const SyncRequiredPage(),
      ),

      // Plan/tablet — adaptive master-detail shell.
      //
      // Two branches, each with its own Navigator: branch 0 = Home
      // (master list), branch 1 = the chat detail. `navigatorContainerBuilder`
      // lays them out by available width:
      //   • tablet + pane budget (≥681dp wide) → master + detail side by side
      //   • otherwise                         → only the active branch
      //
      // On phone the detail branch is never activated — tapping a session
      // does a full-screen root `push('/chat')` instead (see Home._open),
      // which preserves native back/swipe. The detail branch only renders
      // on tablet, where it reacts to [SessionSelection].
      StatefulShellRoute(
        builder: (ctx, st, navShell) => navShell,
        navigatorContainerBuilder: (ctx, navShell, children) {
          // Two panes only when wide AND Home actually has something to
          // list. On zero-state (no Pi / empty) we collapse to the single
          // active branch (the master, full-width + centered) so the user
          // doesn't see a cramped 360 column next to a big empty
          // placeholder.
          final twoPane =
              canUseTwoPaneLayout(ctx) && !ctx.watch<ShellLayout>().isZeroState;
          _logLayoutModeTransition(ctx, twoPane);
          final content = !twoPane
              ? children[navShell.currentIndex]
              // On a tablet with asymmetric landscape safe areas, each pane's
              // own SafeArea reads the *full screen* insets and pads the edge
              // facing the divider too. Strip only those divider-facing insets.
              : Row(
                  children: [
                    SizedBox(width: kMasterPaneWidth, child: children[0]),
                    VerticalDivider(
                      width: kPaneDividerWidth,
                      thickness: kPaneDividerWidth,
                      color: ctx.colors.borderStrong,
                    ),
                    Expanded(
                      child: MediaQuery.removePadding(
                        context: ctx,
                        removeLeft: true,
                        child: children[1],
                      ),
                    ),
                  ],
                );
          return PaneCollapseImeDismissal(
            twoPane: twoPane,
            onWatchdogRecovery: () => _logLayoutModeTransition(
              ctx,
              twoPane,
              trigger: 'ime-watchdog',
              force: true,
            ),
            child: content,
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (ctx, st) {
                  final isolateKeyboard =
                      canUseTwoPaneLayout(ctx) &&
                      !ctx.watch<ShellLayout>().isZeroState;
                  return MultiProvider(
                    providers: [
                      ViewmodelProvider<HomeViewModel>(),
                      ViewmodelProvider<UpdateBannerViewModel>(),
                    ],
                    child: MasterPaneHomeSurface(
                      isolateKeyboard: isolateKeyboard,
                      child: const HomePage(),
                    ),
                  );
                },
              ),
            ],
          ),
          // `preload: true` so the detail branch is built up-front and
          // renders in the tablet's right pane at launch (showing the
          // placeholder) without first navigating into it. On phone the
          // branch is built but never displayed.
          StatefulShellBranch(
            preload: true,
            routes: [
              GoRoute(
                path: '/session',
                builder: (ctx, st) => const _DetailPane(),
              ),
            ],
          ),
        ],
      ),

      // QR pairing flow
      GoRoute(
        path: '/pair',
        builder: (ctx, st) =>
            ViewmodelProvider<PairingViewModel>(child: const PairingPage()),
      ),

      // Onboarding (plan 14) — 3-step flow shown when the app has
      // never been paired AND the user hasn't opted out. Provides
      // both OnboardingViewModel (state machine) AND PairingViewModel
      // (step 3 embeds the QR scanner reusing existing pair flow).
      GoRoute(
        path: '/onboarding',
        builder: (ctx, st) => MultiProvider(
          providers: [
            ViewmodelProvider<OnboardingViewModel>(),
            ViewmodelProvider<PairingViewModel>(),
          ],
          child: const OnboardingPage(),
        ),
      ),

      // Chat screen — PHONE full-screen path (root navigator, above the
      // shell), so it keeps native back/swipe. On tablet the chat lives
      // in the detail branch instead (see _detailPane). Entered by
      // tapping a session in /home.
      // Plan/24-fix-title: Home passes the already-known peer label
      // (nickname / sessionName) via `extra` so the AppBar renders
      // the right title from frame 1 instead of waiting for the
      // first `room_meta_updated` to arrive. Keeps reactivity to
      // room metadata changes that come later through the
      // ChatViewModel.
      GoRoute(
        path: '/chat',
        builder: (ctx, st) {
          final extra = st.extra;
          String? initialTitle;
          String? initialDevice;
          var initialOnline = false;
          if (extra is Map) {
            final t = extra['title'];
            if (t is String && t.isNotEmpty) initialTitle = t;
            // Plan/32g — device (Mac) label Home already knows, so AppBar
            // line 2 renders immediately (no async PeerRecord wait).
            final d = extra['device'];
            if (d is String && d.isNotEmpty) initialDevice = d;
            // Live state of the tile → initial status dot (no reconnect flash).
            initialOnline = extra['online'] == true;
          }
          return MultiProvider(
            providers: [
              ViewmodelProvider<ChatViewModel>(),
              ViewmodelProvider<VoiceInputViewModel>(),
              ViewmodelProvider<AttachmentViewModel>(),
            ],
            child: ChatPage(
              initialTitle: initialTitle,
              initialDevice: initialDevice,
              initialOnline: initialOnline,
            ),
          );
        },
      ),

      // Settings (entered from /home menu)
      GoRoute(
        path: '/settings',
        builder: (ctx, st) =>
            ViewmodelProvider<SettingsViewModel>(child: const SettingsPage()),
      ),
    ],
  );
  return AppRouterOwner(
    router: router,
    bootState: boot,
    retryBoot: retryBoot,
    stopPolling: meshSync.stopPolling,
  );
}

/// Detail pane for the tablet's right side. Reacts to [SessionSelection]:
/// shows the placeholder until a session is picked, then the chat — keyed
/// by `(epk, room, sessionId)` so switching canonical Pi sessions in the same
/// relay room tears down the old ChatViewModel and builds a fresh one. The VM
/// still reads `Preferences.selectedPeerEpk`, already set by Home._open.
class _DetailPane extends StatelessWidget {
  const _DetailPane();

  @override
  Widget build(BuildContext context) {
    final sel = context.watch<SessionSelection>();
    if (sel.current == null) {
      return const DetailPlaceholder();
    }
    return MultiProvider(
      key: ValueKey(
        'chat-${sel.current!.epk}-${sel.current!.roomId}-${sel.current!.sessionId}',
      ),
      providers: [
        ViewmodelProvider<ChatViewModel>(),
        ViewmodelProvider<VoiceInputViewModel>(),
        ViewmodelProvider<AttachmentViewModel>(),
      ],
      child: ChatPage(
        initialTitle: sel.current!.title,
        initialDevice: sel.current!.device.isEmpty ? null : sel.current!.device,
        initialOnline: sel.current!.online,
        showBack: false,
      ),
    );
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash({required this.state, required this.onRetry});

  final BootState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg,
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final failure = state.failure;
          if (failure != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 32,
                      color: context.colors.error,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      failure.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.colors.text,
                        fontFamily: kMonoFamily,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: state.loading ? null : onRetry,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          return Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: context.colors.accent,
                strokeWidth: 2,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Emit a layoutMode debug event when the two-pane verdict or its driving
/// metrics change. Field diagnosis for phantom half-screen layouts on
/// phone-class displays (Fold display-switch timing): the capture shows the
/// exact window metrics the shell believed at the transition.
void _logLayoutModeTransition(
  BuildContext ctx,
  bool twoPane, {
  String trigger = 'shell-builder',
  bool force = false,
}) {
  final size = MediaQuery.sizeOf(ctx);
  final dpr = MediaQuery.devicePixelRatioOf(ctx);
  final ime = MediaQuery.viewInsetsOf(ctx).bottom;
  final key = (twoPane, size.width, size.height, dpr, ime);
  if (!force && _lastLayoutKey == key) return;
  _lastLayoutKey = key;
  injector.get<DebugLog>().log(
    LayoutModeEvent(
      ts: DateTime.now().toUtc(),
      twoPane: twoPane,
      widthDp: size.width.round(),
      heightDp: size.height.round(),
      shortestSideDp: size.shortestSide.round(),
      devicePixelRatio: dpr,
      imeBottomDp: ime.round(),
      trigger: trigger,
    ),
  );
}

Object? _lastLayoutKey;

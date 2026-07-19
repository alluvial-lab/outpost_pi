import 'package:app/config/dependencies.dart';
import 'package:app/data/local/boxes.dart';
import 'package:app/data/mesh/mesh_sync_service.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Reconcile connection and session state when the app returns to foreground.
///
/// An online connection rehydrates authoritative relay snapshots before asking
/// SyncService for history. Retrying/offline connections resume their active
/// peer or boot discovery, so cached UI state never substitutes for live state.
@visibleForTesting
Future<void> reconcileOnAppResume({
  required ConnectionManager connectionManager,
  required void Function() requestSessionSync,
}) async {
  final status = connectionManager.status;
  if (status is StatusOnline) {
    await connectionManager.requestResumeHydration();
    requestSessionSync();
    return;
  }

  if (status is StatusRetrying || status is StatusOffline) {
    final peer = connectionManager.activePeer;
    if (peer != null) {
      await connectionManager.connectTo(peer);
      return;
    }
    await connectionManager.boot();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Provision the transcript-storage key, open encrypted v3 boxes, and wipe
  // volatile runtime state before any service can read or write local data.
  await LocalBoxes.init();
  await setupDependencies();
  // Eagerly construct the SSOT writer so it's consuming the channel from boot
  // (messages can arrive before the chat screen mounts).
  injector.get<SyncService>();
  runApp(const OutpostPiApp());
}

class OutpostPiApp extends StatefulWidget {
  const OutpostPiApp({super.key});

  @override
  State<OutpostPiApp> createState() => _OutpostPiAppState();
}

class _OutpostPiAppState extends State<OutpostPiApp>
    with WidgetsBindingObserver {
  late final _routerOwner = buildRouter(
    injector.get<PairingStorage>(),
    injector.get<ConnectionManager>(),
    injector.get<Preferences>(),
    injector.get<OwnerIdentityBridge>(),
    injector.get<MeshSyncService>(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routerOwner.dispose();
    disposeDependencies();
    super.dispose();
  }

  /// Plan 24 — keep the mesh poll timer aligned with the app's
  /// foreground lifecycle. Polling runs ONLY while resumed; in
  /// inactive/paused/hidden/detached we cancel so we don't drain the
  /// battery (and we'll resync via `pullOnDemand` on the next resume +
  /// boot path).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final meshSync = injector.get<MeshSyncService>();
    final connectionManager = injector.get<ConnectionManager>();
    final syncService = injector.get<SyncService>();

    switch (state) {
      case AppLifecycleState.resumed:
        meshSync.startPolling();
        // ignore: unawaited_futures
        meshSync.pullOnDemand();
        // ignore: unawaited_futures
        reconcileOnAppResume(
          connectionManager: connectionManager,
          requestSessionSync: syncService.requestSync,
        );
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        meshSync.stopPolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<Preferences>.value(
          value: injector.get<Preferences>(),
        ),
        // App-global UI selection — read by the Home list (highlight) and
        // the tablet detail pane. Lives above the router so every route
        // (both shell branches) resolves the same instance.
        ChangeNotifierProvider<SessionSelection>.value(
          value: injector.get<SessionSelection>(),
        ),
        // Shell layout state — lets the adaptive shell collapse the split
        // into a single centered pane on zero-state Home (no Pi / empty).
        ChangeNotifierProvider<ShellLayout>.value(
          value: injector.get<ShellLayout>(),
        ),
      ],
      // Theme is reactive: toggling the mode in Settings notifies
      // [Preferences] → this Consumer rebuilds → MaterialApp swaps theme.
      child: Consumer<Preferences>(
        builder: (context, prefs, _) => MaterialApp.router(
          title: 'Outpost-Pi',
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: prefs.themeMode,
          routerConfig: _routerOwner.router,
          debugShowCheckedModeBanner: false,
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:app/config/dependencies.dart';
import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/transcript_storage_key.dart';
import 'package:app/data/mesh/mesh_sync_service.dart';
import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/sync/sync_service.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/routing/adaptive.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/storage_recovery/transcript_storage_recovery_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Reconcile connection and session state when the app returns to foreground.
///
/// An online connection rehydrates authoritative relay snapshots before asking
/// SyncService for history. An overdue connecting attempt is expired so its
/// retry ladder can restart; retrying/offline connections resume their active
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

  if (status is StatusConnecting) {
    await connectionManager.expireOverdueConnectOnResume();
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    OutpostPiBootstrap(
      initializeStorage: LocalBoxes.init,
      discardUnreadableTranscripts: LocalBoxes.discardUnreadableTranscripts,
      initializeDependencies: () async {
        await setupDependencies();
        // Eagerly construct the SSOT writer so it's consuming the channel from
        // boot (messages can arrive before the chat screen mounts).
        injector.get<SyncService>();
      },
      appBuilder: (_) => const OutpostPiApp(),
    ),
  );
}

enum _BootstrapPhase { loading, recovery, ready }

/// Gate dependency setup and the production router on encrypted storage.
///
/// Only a recognized lost-key/ciphertext failure reaches the recovery UI. A
/// confirmed discard returns through the same [initializeStorage] boundary;
/// no recovery path can open transcript data without a fresh successful init.
class OutpostPiBootstrap extends StatefulWidget {
  const OutpostPiBootstrap({
    super.key,
    required this.initializeStorage,
    required this.discardUnreadableTranscripts,
    required this.initializeDependencies,
    required this.appBuilder,
  });

  final Future<void> Function() initializeStorage;
  final Future<void> Function() discardUnreadableTranscripts;
  final Future<void> Function() initializeDependencies;
  final WidgetBuilder appBuilder;

  @override
  State<OutpostPiBootstrap> createState() => _OutpostPiBootstrapState();
}

class _OutpostPiBootstrapState extends State<OutpostPiBootstrap> {
  _BootstrapPhase _phase = _BootstrapPhase.loading;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap({bool discard = false}) async {
    final generation = ++_generation;
    if (mounted) setState(() => _phase = _BootstrapPhase.loading);
    try {
      if (discard) await widget.discardUnreadableTranscripts();
      if (!mounted || generation != _generation) return;
      await widget.initializeStorage();
      if (!mounted || generation != _generation) return;
      await widget.initializeDependencies();
      if (!mounted || generation != _generation) return;
      setState(() => _phase = _BootstrapPhase.ready);
    } on TranscriptStorageKeyException catch (error) {
      if (!mounted || generation != _generation) return;
      if (error.canDiscardUnreadableTranscripts) {
        setState(() => _phase = _BootstrapPhase.recovery);
        return;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _BootstrapPhase.ready => widget.appBuilder(context),
      _BootstrapPhase.recovery => MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        home: TranscriptStorageRecoveryPage(
          onRetry: _bootstrap,
          onDiscard: () => _bootstrap(discard: true),
        ),
      ),
      _BootstrapPhase.loading => MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    };
  }
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
    unawaited(disposeDependencies());
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

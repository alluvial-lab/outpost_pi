import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:cockpit/app/app_module.dart';
import 'package:cockpit/app/app_widget.dart';
import 'package:cockpit/app/cockpit/data/rpc/pi_process_registry.dart';
import 'package:cockpit/app/core/data/lsp/lsp_process_registry.dart';
import 'package:cockpit/app/core/data/relay/pairing_seam_cleanup.dart';
import 'package:cockpit/app/core/data/repositories/json_settings_store.dart';
import 'package:cockpit/app/core/data/storage/json_state_store.dart';
import 'package:cockpit/app/core/data/storage/legacy_hive_migrator.dart';
import 'package:cockpit/app/core/data/storage/storage_paths.dart';
import 'package:cockpit/app/core/domain/contracts/state_store.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/core/ui/bootstrap_error_screen.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

/// Number of attempts used by the injectable bootstrap store-open seam.
const int defaultStoreOpenAttempts = 10;

typedef BootstrapTask = Future<void> Function();
typedef BootstrapPreflight = Future<void> Function();
typedef BootstrapStoreOpener = Future<Object?> Function(String name);

/// Run Cockpit startup and render a recoverable error when it cannot complete.
///
/// The bootstrap task is injectable so the composition boundary can be tested
/// without depending on a particular persistence implementation.
Future<void> main() => runCockpit();

/// Execute the startup boundary that production uses before showing the app.
///
/// Startup failures are consumed here, after the complete bootstrap task has
/// unwound, so they cannot escape as an unhandled asynchronous exception.
Future<void> runCockpit({BootstrapTask? bootstrap}) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await (bootstrap ?? bootstrapCockpit)();
  } catch (error, stack) {
    debugPrint('Cockpit bootstrap failed: $error\n$stack');
    runApp(BootstrapErrorApp(error: error));
  }
}

/// Initialize Cockpit and compose its production dependency graph.
///
/// [openStore] is a storage-neutral test seam retained at the complete
/// bootstrap boundary. Production resolves platform paths, commits the
/// marker-last legacy migration, and opens atomic JSON stores. [preflight]
/// isolates native startup preparation for deterministic tests.
Future<void> bootstrapCockpit({
  BootstrapPreflight? preflight,
  BootstrapStoreOpener? openStore,
  int retryAttempts = defaultStoreOpenAttempts,
  Duration retryDelay = const Duration(milliseconds: 300),
}) async {
  await (preflight ?? _prepareBootstrap)();

  final StateStoreFactory stateStores;
  if (openStore != null) {
    stateStores = _RetryingStateStoreFactory(
      openStore,
      attempts: retryAttempts,
      delay: retryDelay,
    );
  } else {
    final stateDirectory = await CockpitStoragePaths.stateDirectory();
    await LegacyHiveMigrator(
      stateDirectory: stateDirectory,
      legacyDirectories: await CockpitStoragePaths.legacyHiveDirectories(),
    ).runIfNeeded();
    stateStores = JsonStateStoreFactory(stateDirectory);
  }

  final settingsState = await stateStores.open(JsonSettingsStore.storeName);
  final settings = SettingsController(JsonSettingsStore(settingsState));
  await settings.load();

  final windowState = await stateStores.open('window_state');
  await _setupWindow(windowState);

  final config = await PiSpawnConfig.resolve();
  final appModule = await buildAppModule(
    config: config,
    stateStores: stateStores,
  );

  runApp(
    _WindowStateKeeper(
      store: windowState,
      stateStores: stateStores,
      child: ModularApp(
        module: appModule,
        provide: (s) => s.addChangeNotifier<SettingsController>(() => settings),
        child: const AppRoot(),
      ),
    ),
  );
}

Future<void> _prepareBootstrap() async {
  MediaKit.ensureInitialized();

  // Clean resources from a prior crash before any new process can start.
  await PiProcessRegistry.cleanOrphans();
  await LspProcessRegistry.cleanOrphans();
  await PairingSeamCleanup.sweep();
}

Future<T> _withFileSystemRetry<T>(
  Future<T> Function() operation, {
  required int attempts,
  required Duration delay,
}) async {
  if (attempts < 1) {
    throw ArgumentError.value(attempts, 'attempts', 'Must be positive');
  }
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await operation();
    } on FileSystemException {
      if (attempt == attempts) rethrow;
      if (delay > Duration.zero) await Future<void>.delayed(delay);
    }
  }
  throw StateError('State-store retry exhausted without a result');
}

final class _RetryingStateStoreFactory implements StateStoreFactory {
  _RetryingStateStoreFactory(
    this._openStore, {
    required this.attempts,
    required this.delay,
  });

  final BootstrapStoreOpener _openStore;
  final int attempts;
  final Duration delay;
  final Map<String, StateStore> _stores = <String, StateStore>{};

  @override
  Future<StateStore> open(String name) async {
    final existing = _stores[name];
    if (existing != null) return existing;
    final opened = await _withFileSystemRetry<Object?>(
      () => _openStore(name),
      attempts: attempts,
      delay: delay,
    );
    if (opened is! StateStore) {
      throw StateError('Bootstrap store opener returned an invalid store');
    }
    _stores[name] = opened;
    return opened;
  }

  @override
  Future<void> flushAll() => Future.wait<void>(
    _stores.values.map((StateStore store) => store.flush()),
  );
}

/// Flush state before Flutter approves a requested desktop application exit.
final class StateStoreExitObserver extends WidgetsBindingObserver {
  StateStoreExitObserver(this._stateStores);

  final StateStoreFactory _stateStores;

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await _stateStores.flushAll();
    return AppExitResponse.exit;
  }
}

/// Hide the native title bar and restore the last window size.
Future<void> _setupWindow(StateStore store) async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
  await windowManager.ensureInitialized();
  final width = (store.get('width') as num?)?.toDouble() ?? 1280;
  final height = (store.get('height') as num?)?.toDouble() ?? 720;
  final options = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    minimumSize: const Size(720, 480),
    size: Size(width, height),
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

/// Listen for resizes and persist the window size with debounce.
final class _WindowStateKeeper extends StatefulWidget {
  const _WindowStateKeeper({
    required this.store,
    required this.stateStores,
    required this.child,
  });

  final StateStore store;
  final StateStoreFactory stateStores;
  final Widget child;

  @override
  State<_WindowStateKeeper> createState() => _WindowStateKeeperState();
}

final class _WindowStateKeeperState extends State<_WindowStateKeeper>
    with WindowListener {
  Timer? _debounce;
  late final StateStoreExitObserver _exitObserver;

  @override
  void initState() {
    super.initState();
    _exitObserver = StateStoreExitObserver(widget.stateStores);
    WidgetsBinding.instance.addObserver(_exitObserver);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(_exitObserver);
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void onWindowResize() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final size = await windowManager.getSize();
      await widget.store.putAll(<String, Object?>{
        'width': size.width,
        'height': size.height,
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

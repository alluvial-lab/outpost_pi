import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/app_module.dart';
import 'package:cockpit/app/app_widget.dart';
import 'package:cockpit/app/cockpit/data/rpc/pi_process_registry.dart';
import 'package:cockpit/app/core/data/lsp/lsp_process_registry.dart';
import 'package:cockpit/app/core/data/relay/pairing_seam_cleanup.dart';
import 'package:cockpit/app/core/data/hive_box_opener.dart';
import 'package:cockpit/app/core/data/repositories/hive_settings_store.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/core/ui/bootstrap_error_screen.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

/// Root subdirectory for Hive boxes. In debug mode uses `cockpit-debug` to
/// avoid colliding with the production build's boxes (which is often left open
/// in parallel during development). All boxes — including `window_state` —
/// inherit this directory via `Hive.initFlutter`.
const String hiveSubdir = kDebugMode ? 'cockpit-debug' : 'cockpit';

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
/// [openStore] is the raw persistence boundary. The default adapter opens a
/// Hive box, while tests can inject any store implementation and exercise the
/// retry and error-rendering behavior without naming that backend. [preflight]
/// isolates native startup preparation from that boundary for deterministic
/// tests.
Future<void> bootstrapCockpit({
  BootstrapPreflight? preflight,
  BootstrapStoreOpener? openStore,
  int retryAttempts = defaultHiveOpenAttempts,
  Duration retryDelay = const Duration(milliseconds: 300),
}) async {
  final prepare = preflight ?? _prepareBootstrap;
  final open = openStore ?? _openHiveStore;
  Future<Object?> openWithRetry(String name) => withFileSystemRetry(
    () => open(name),
    attempts: retryAttempts,
    delay: retryDelay,
  );

  await prepare();

  // The feature boxes are opened by their own async builders (see
  // buildCockpitModule); here only the settings box, which SettingsController
  // needs before the first frame.
  final settingsBox =
      await openWithRetry(HiveSettingsStore.boxName) as Box<dynamic>;

  // Preferences loaded BEFORE the first frame → the app opens in the saved
  // theme (no flash). App-scoped: provided via `ModularApp.provide`, above the
  // `ShadcnApp` → changing theme/font repaints everything.
  final settings = SettingsController(HiveSettingsStore(settingsBox));
  await settings.load();

  final winBox = await openWithRetry('window_state') as Box<dynamic>;
  await _setupWindow(winBox);

  // The only threaded value: lives in core (root-owned) and the features
  // resolve it upward. The module is a `Future` because the cockpit opens its
  // own boxes.
  final config = await PiSpawnConfig.resolve();
  final appModule = await buildAppModule(config: config);

  runApp(
    _WindowStateKeeper(
      box: winBox,
      child: ModularApp(
        module: appModule,
        provide: (s) => s.addChangeNotifier<SettingsController>(() => settings),
        child: const AppRoot(),
      ),
    ),
  );
}

Future<void> _prepareBootstrap() async {
  // Plan 46 — initialize media_kit (libmpv) before any Player.
  MediaKit.ensureInitialized();

  // Kills orphaned `pi --mode rpc` processes and language servers (LSP) from
  // the previous cycle before any new spawn (covers hot restart and cold
  // restart after a crash).
  await PiProcessRegistry.cleanOrphans();
  await LspProcessRegistry.cleanOrphans();
  await PairingSeamCleanup.sweep();

  // Own subdirectory; in debug mode separated from the production build.
  await Hive.initFlutter(hiveSubdir);
}

Future<Object?> _openHiveStore(String name) => Hive.openBox<dynamic>(name);

/// Hides the native title bar and restores the last window size.
Future<void> _setupWindow(Box<dynamic> winBox) async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
  await windowManager.ensureInitialized();
  final w = (winBox.get('width') as num?)?.toDouble() ?? 1280;
  final h = (winBox.get('height') as num?)?.toDouble() ?? 720;
  final options = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    minimumSize: const Size(720, 480),
    size: Size(w, h),
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

/// Listens for resizes and persists the window size with debounce.
class _WindowStateKeeper extends StatefulWidget {
  const _WindowStateKeeper({required this.box, required this.child});
  final Box<dynamic> box;
  final Widget child;

  @override
  State<_WindowStateKeeper> createState() => _WindowStateKeeperState();
}

class _WindowStateKeeperState extends State<_WindowStateKeeper>
    with WindowListener {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void onWindowResize() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final size = await windowManager.getSize();
      await widget.box.put('width', size.width);
      await widget.box.put('height', size.height);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

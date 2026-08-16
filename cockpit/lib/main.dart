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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _bootstrap();
  } catch (error, stack) {
    debugPrint('Cockpit bootstrap failed: $error\n$stack');
    runApp(BootstrapErrorApp(error: error));
  }
}

Future<void> _bootstrap() async {
  // Plan 46 — initialize media_kit (libmpv) before any Player.
  MediaKit.ensureInitialized();

  // Kills orphaned `pi --mode rpc` processes and language servers (LSP) from
  // the previous cycle before any new spawn (covers hot restart and cold
  // restart after a crash).
  await PiProcessRegistry.cleanOrphans();
  await LspProcessRegistry.cleanOrphans();
  await PairingSeamCleanup.sweep();

  // Own subdirectory; in debug mode separated from the production build. The
  // feature boxes are opened by their own async builders (see
  // buildCockpitModule); here only the settings box, which SettingsController
  // needs before the first frame.
  await Hive.initFlutter(hiveSubdir);
  final settingsBox = await openHiveBoxWithRetry<dynamic>(
    HiveSettingsStore.boxName,
  );

  // Preferences loaded BEFORE the first frame → the app opens in the saved
  // theme (no flash). App-scoped: provided via `ModularApp.provide`, above the
  // `ShadcnApp` → changing theme/font repaints everything.
  final settings = SettingsController(HiveSettingsStore(settingsBox));
  await settings.load();

  final winBox = await openHiveBoxWithRetry<dynamic>('window_state');
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

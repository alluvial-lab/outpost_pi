import 'package:cockpit/app/cockpit/domain/entities/launchable_app.dart';

/// Detect installed IDEs and open paths in them.
abstract class AppLauncherGateway {
  /// Return the apps available on the system in default-preference order.
  /// Finder/Explorer is always included last.
  Future<List<LaunchableApp>> probe();

  /// Open [path] in [app]. IDEs use `open -a`; Finder uses `open`.
  Future<void> launch(LaunchableApp app, String path);

  /// Open [path] in the **OS default app** for that file type (macOS `open`,
  /// Linux `xdg-open`, Windows `start`). Supports both files and folders.
  Future<void> openWithDefaultApp(String path);
}

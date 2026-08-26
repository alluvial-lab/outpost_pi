import 'dart:async';

/// Track the current native self-update phase for Sparkle or WinSparkle.
///
/// Updates are best-effort: every failure becomes [error], and the card falls
/// back to the notification path without disrupting startup.
enum SelfUpdatePhase {
  /// Indicate that no update is pending, before a check or on the latest version.
  idle,

  /// Indicate that the appcast is being checked.
  checking,

  /// Indicate that a new version is downloading silently in the background.
  downloading,

  /// Indicate that a verified artifact is ready to install after a restart.
  downloaded,

  /// Indicate a network, signature, or parsing failure logged without UI noise.
  error,
}

/// Expose observable [SelfUpdater] state.
///
/// [version] is present when an update is available or downloaded, and
/// [message] is present on error.
class SelfUpdateState {
  const SelfUpdateState(this.phase, {this.version, this.message});

  const SelfUpdateState.idle() : this(SelfUpdatePhase.idle);

  final SelfUpdatePhase phase;
  final String? version;
  final String? message;

  /// Return `true` once the artifact is downloaded and awaits a restart.
  bool get isReadyToInstall => phase == SelfUpdatePhase.downloaded;

  /// Return `true` while an update is downloading or ready for the UI card.
  bool get hasPendingUpdate =>
      phase == SelfUpdatePhase.downloading ||
      phase == SelfUpdatePhase.downloaded;
}

/// Manage native self-updates with **Sparkle on macOS and WinSparkle on
/// Windows** through the `auto_updater` plugin.
///
/// On unsupported platforms such as Linux, [isSupported] is `false` and methods
/// are no-ops. The notification and manual-download path through
/// `UpdateChecker` and `UpdateCard` takes over.
///
/// Under plan 47's hybrid UX decision B, checks and downloads run **in the
/// background** without a native dialog. Only the app's card is visible, driven
/// by [state] and [changes]. Applying an update follows silent-restart decision
/// C: the native engine exits and relaunches the app. On the next startup,
/// `PiProcessRegistry.cleanOrphans` reaps child `pi` agents and persisted state
/// respawns them.
abstract class SelfUpdater {
  /// Report whether a native update engine exists on macOS or Windows.
  bool get isSupported;

  /// Return a synchronous state snapshot for the card's first render.
  SelfUpdateState get state;

  /// Emit [state] transitions that prompt the UI to render again.
  Stream<SelfUpdateState> get changes;

  /// Start the native engine, configure its feed and listener, and schedule
  /// periodic checks.
  ///
  /// This operation is idempotent and a no-op when [isSupported] is `false`.
  Future<void> initialize();

  /// Trigger an update check, suppressing native UI when [inBackground] is true.
  Future<void> checkForUpdates({bool inBackground = true});

  /// Install the downloaded update and relaunch, or do nothing if none exists.
  Future<void> applyDownloadedUpdate();

  /// Release the native listener and state stream.
  void dispose();
}

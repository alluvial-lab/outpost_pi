import 'dart:async';

import 'package:auto_updater/auto_updater.dart';
import 'package:cockpit/app/cockpit/domain/contracts/self_updater.dart';
import 'package:flutter/foundation.dart';

/// Drive native self-updates through [autoUpdater]: Sparkle on macOS and
/// WinSparkle on Windows.
///
/// Implements [SelfUpdater] and maps native [UpdaterListener] events to
/// [SelfUpdateState]. Boot and scheduled checks run silently with
/// `inBackground: true`. On macOS, `SUEnableAutomaticChecks` and
/// `SUAutomaticallyUpdate` let Sparkle download in the background and install
/// on the next quit while [changes] keeps the card current.
/// [applyDownloadedUpdate] checks again in the foreground so the native engine
/// can install and relaunch an already-downloaded update.
///
/// The plugin uses `SPUStandardUserDriver`, so the final installation step may
/// show minimal native UI that this adapter cannot fully suppress. Boot checks
/// remain silent.
class AutoUpdaterSelfUpdater with UpdaterListener implements SelfUpdater {
  AutoUpdaterSelfUpdater({
    required this.feedUrl,
    this.checkInterval = const Duration(hours: 24),
  });

  /// Use the platform appcast (`appcast-macos.xml` or `appcast-windows.xml`).
  final String feedUrl;

  /// Configure the native engine's periodic check interval (minimum 1h; 0 disables it).
  final Duration checkInterval;

  final StreamController<SelfUpdateState> _controller =
      StreamController<SelfUpdateState>.broadcast();
  SelfUpdateState _state = const SelfUpdateState.idle();
  bool _initialized = false;

  @override
  bool get isSupported => true;

  @override
  SelfUpdateState get state => _state;

  @override
  Stream<SelfUpdateState> get changes => _controller.stream;

  void _emit(SelfUpdateState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    autoUpdater.addListener(this);
    await autoUpdater.setFeedURL(feedUrl);
    await autoUpdater.setScheduledCheckInterval(checkInterval.inSeconds);
  }

  @override
  Future<void> checkForUpdates({bool inBackground = true}) async {
    if (!_initialized) await initialize();
    await autoUpdater.checkForUpdates(inBackground: inBackground);
  }

  @override
  Future<void> applyDownloadedUpdate() async {
    if (_state.phase != SelfUpdatePhase.downloaded) return;
    // A foreground recheck makes Sparkle or WinSparkle install the downloaded
    // update and relaunch the app; the native engine owns the restart.
    await autoUpdater.checkForUpdates(inBackground: false);
  }

  // ---- UpdaterListener: native engine events → SelfUpdateState ----

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    _emit(const SelfUpdateState(SelfUpdatePhase.checking));
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? item) {
    // The native engine downloads an available update in the background.
    _emit(
      SelfUpdateState(SelfUpdatePhase.downloading, version: _versionOf(item)),
    );
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    _emit(const SelfUpdateState.idle());
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? item) {
    _emit(
      SelfUpdateState(SelfUpdatePhase.downloaded, version: _versionOf(item)),
    );
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? item) {
    // The adapter does not await this callback during a silent restart, so it
    // cannot block quit or gracefully stop agents here. Child `pi` agents
    // become orphans and `PiProcessRegistry.cleanOrphans` reaps their registry
    // PIDs with SIGKILL on the next boot. Persisted state restores the workspace,
    // including panes and tabs.
    debugPrint(
      '[self-update] before quit for update — agents reaped on next boot',
    );
  }

  @override
  void onUpdaterError(UpdaterError? error) {
    _emit(SelfUpdateState(SelfUpdatePhase.error, message: error?.message));
  }

  String? _versionOf(AppcastItem? item) =>
      item?.displayVersionString ?? item?.versionString;

  @override
  void dispose() {
    autoUpdater.removeListener(this);
    if (!_controller.isClosed) _controller.close();
  }
}

import 'dart:async';

import 'package:cockpit/app/cockpit/domain/contracts/dismissed_update_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/self_updater.dart';
import 'package:cockpit/app/cockpit/domain/contracts/update_checker.dart';
import 'package:cockpit/app/cockpit/domain/contracts/url_opener.dart';
import 'package:cockpit/app/cockpit/domain/entities/update_info.dart';
import 'package:cockpit/app/cockpit/domain/value_objects/semver.dart';
import 'package:cockpit/app/cockpit/domain/value_objects/update_target.dart';
import 'package:flutter/foundation.dart';

/// Drive the rail's update card through platform-specific update flows.
///
/// On macOS and Windows, [check] initializes the native [SelfUpdater], which
/// downloads in the background and exposes progress through [SelfUpdateState];
/// the primary action installs the downloaded update and relaunches. On Linux,
/// [check] reads `latest.json` through [UpdateChecker] and offers a newer,
/// non-dismissed artifact for manual download.
///
/// All update operations are best effort: failures stay silent and never block
/// application startup.
class UpdateViewModel extends ChangeNotifier {
  UpdateViewModel(
    this._checker,
    this._dismissed,
    this._opener,
    this._target,
    this._selfUpdater, {
    this.fallbackUrl = _kFallbackUrl,
  });

  final UpdateChecker _checker;
  final DismissedUpdateStore _dismissed;
  final UrlOpener _opener;
  final UpdateTarget _target;
  final SelfUpdater _selfUpdater;

  /// Expose the running application version resolved during startup.
  String get currentVersion => _target.version;

  /// Expose the platform target used to select a Linux download artifact.
  String get platform => _target.platform;
  String get format => _target.format;
  String get arch => _target.arch;

  /// Fall back to this download page when no compatible artifact exists.
  final String fallbackUrl;

  static const String _kFallbackUrl = 'https://outpost-pi.kevoun.com/download';

  UpdateInfo? _available; // Linux notification/manual-download path
  StreamSubscription<SelfUpdateState>? _selfSub;
  bool _selfDismissed = false; // Session-only dismissal in self-update mode
  bool _disposed = false;

  /// Report whether this platform has a native self-update engine.
  bool get isSelfUpdate => _selfUpdater.isSupported;

  // ---- Unified state consumed by the card ----

  /// Report whether the update card should be visible.
  bool get hasUpdate {
    if (isSelfUpdate) {
      return !_selfDismissed && _selfUpdater.state.hasPendingUpdate;
    }
    return _available != null;
  }

  /// Report whether a self-update artifact is downloaded and ready to install.
  bool get isReadyToInstall =>
      isSelfUpdate && _selfUpdater.state.isReadyToInstall;

  /// Expose the update version, or `null` until it is known.
  String? get updateVersion =>
      isSelfUpdate ? _selfUpdater.state.version : _available?.version;

  /// Build the update card title for the current phase.
  String get cardTitle =>
      isReadyToInstall ? 'Update ready' : 'Update available';

  /// Build the update card subtitle for the current mode and phase.
  String get cardSubtitle {
    final v = updateVersion ?? '';
    if (isSelfUpdate) {
      return isReadyToInstall ? 'v$v — restart to install' : 'Downloading v$v…';
    }
    return 'v$v — click to download';
  }

  // ---- Startup ----

  /// Check for updates and publish whether the card should appear.
  ///
  /// Native self-update subscribes to engine changes before initialization;
  /// Linux fetches and filters the manifest. Failures remain silent.
  Future<void> check() async {
    if (isSelfUpdate) {
      _selfSub ??= _selfUpdater.changes.listen((_) => _safeNotify());
      await _selfUpdater.initialize();
      await _selfUpdater.checkForUpdates(inBackground: true);
      return;
    }
    // Linux uses notification plus manual download.
    final latest = await _checker.fetchLatest();
    if (latest == null) return; // No network, manifest, or valid update.
    if (!isNewerVersion(latest.version, currentVersion)) return; // Not newer.
    if (_dismissed.dismissedVersion() == latest.version) return; // Dismissed.
    _available = latest;
    _safeNotify();
  }

  // ---- Card actions ----

  /// Perform the update card's primary action.
  ///
  /// Native self-update installs and relaunches with the downloaded update;
  /// Linux opens the selected artifact in the browser.
  Future<void> primaryAction() async {
    if (isSelfUpdate) {
      await _selfUpdater.applyDownloadedUpdate();
      return;
    }
    await _download();
  }

  /// Dismiss the current update card.
  ///
  /// Self-update dismissal lasts only for this session; Linux persists the
  /// dismissed version so it does not reappear.
  Future<void> dismiss() async {
    if (isSelfUpdate) {
      _selfDismissed = true;
      _safeNotify();
      return;
    }
    final v = _available?.version;
    _available = null;
    _safeNotify();
    if (v != null) await _dismissed.dismiss(v);
  }

  /// Open the current platform artifact or the fallback download page.
  Future<void> _download() async {
    final info = _available;
    if (info == null) return;
    final artifact = info.artifactFor(
      platform: platform,
      format: format,
      arch: arch,
    );
    await _opener.open(artifact?.url ?? fallbackUrl);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _selfSub?.cancel();
    super.dispose();
  }
}

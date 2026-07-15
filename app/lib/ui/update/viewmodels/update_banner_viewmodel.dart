import 'package:app/domain/contracts/dismissed_update_store.dart';
import 'package:app/domain/contracts/update_checker.dart';
import 'package:app/domain/contracts/url_opener.dart';
import 'package:app/domain/value_objects/semver.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/update/states/update_banner_state.dart';

/// Drive the Android-only in-app update banner (plan 44, step 3).
///
/// [check] runs when Home mounts and emits [UpdateBannerVisible] only for a
/// newer, non-dismissed manifest version. Failures are intentionally silent.
/// [enabled] receives `Platform.isAndroid` at boot, keeping the no-iOS rule
/// testable without depending on the host that runs `flutter test`.
class UpdateBannerViewModel extends ViewModel<UpdateBannerState> {
  UpdateBannerViewModel(
    this._checker,
    this._dismissed,
    this._opener, {
    required this.currentVersion,
    required this.enabled,
    this.platform = 'android',
    this.format = 'apk',
    this.arch = 'universal',
    this.fallbackUrl = _kFallbackUrl,
  }) : super(const UpdateBannerHidden());

  final UpdateChecker _checker;
  final DismissedUpdateStore _dismissed;
  final UrlOpener _opener;

  /// Identify the running app version injected from `package_info` at boot.
  final String currentVersion;

  /// Enable the banner only on Android; iOS updates through the App Store.
  final bool enabled;

  /// Select the downloadable artifact coordinates for the universal Android APK.
  final String platform;
  final String format;
  final String arch;

  /// Fall back to the site's download page when no compatible artifact exists.
  final String fallbackUrl;

  static const String _kFallbackUrl = 'https://outpost-pi.kevoun.com/download';

  bool _checked = false;
  bool _disposed = false;

  /// Fetch the manifest and determine whether to show the banner.
  ///
  /// This is silent on failure and idempotent per instance: a remount creates
  /// a new instance and checks again, while one instance checks only once.
  Future<void> check() async {
    if (!enabled) return; // iOS / non-Android: never show the banner.
    if (_checked) return;
    _checked = true;

    final latest = await _checker.fetchLatest();
    if (_disposed) return;
    if (latest == null) return; // No network or invalid manifest: no banner.
    if (!isNewerVersion(latest.version, currentVersion)) {
      return; // Equal or lower version: no banner.
    }

    final dismissed = await _dismissed.dismissedVersion();
    if (_disposed) return;
    if (dismissed == latest.version) return; // Dismissed version: no banner.

    emit(UpdateBannerVisible(latest));
  }

  /// Hide the banner and persist its version as dismissed.
  ///
  /// It remains hidden for that version but returns for a newer one.
  Future<void> dismiss() async {
    final current = state;
    if (current is! UpdateBannerVisible) return;
    final version = current.info.version;
    emit(const UpdateBannerHidden());
    await _dismissed.dismiss(version);
  }

  /// Open the Android APK download in the browser.
  ///
  /// Opens the site download page when the manifest has no compatible artifact.
  Future<void> download() async {
    final current = state;
    if (current is! UpdateBannerVisible) return;
    final artifact = current.info.artifactFor(
      platform: platform,
      format: format,
      arch: arch,
    );
    await _opener.open(artifact?.url ?? fallbackUrl);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

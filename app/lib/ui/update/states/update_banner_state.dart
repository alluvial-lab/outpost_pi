import 'package:app/domain/entities/update_info.dart';

/// Represent the in-app update banner (plan 44).
///
/// The banner is hidden when there is nothing actionable—on iOS, without an
/// update, after dismissal, or when the manifest is unavailable—or visible
/// with the [UpdateInfo] to announce.
sealed class UpdateBannerState {
  const UpdateBannerState();
}

/// Hide the banner when there is no update to announce.
///
/// The const instance lets `emit` deduplicate by identity without a manual
/// equality override.
final class UpdateBannerHidden extends UpdateBannerState {
  const UpdateBannerHidden();
}

/// Show a newer version that has not been dismissed.
final class UpdateBannerVisible extends UpdateBannerState {
  const UpdateBannerVisible(this.info);

  final UpdateInfo info;

  // Version equality avoids rebuilding when the same manifest is re-emitted.
  @override
  bool operator ==(Object other) =>
      other is UpdateBannerVisible && other.info.version == info.version;

  @override
  int get hashCode => info.version.hashCode;
}

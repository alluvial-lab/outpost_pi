/// Persist the update version the user dismissed by closing its card.
///
/// This domain contract is implemented by secure storage in `data/update/`.
/// A dismissed version stays hidden, while a newer version becomes visible.
abstract class DismissedUpdateStore {
  /// Return the last dismissed version, if any.
  Future<String?> dismissedVersion();

  /// Mark [version] as dismissed.
  Future<void> dismiss(String version);
}

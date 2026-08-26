/// Persist the update version the user **dismissed** by closing its card.
///
/// The card stays hidden for that version but reappears when a newer version
/// is released; the concrete persistence backend remains outside domain.
abstract class DismissedUpdateStore {
  /// Return the last dismissed version, or `null` if none was dismissed.
  String? dismissedVersion();

  /// Mark [version] as dismissed.
  Future<void> dismiss(String version);
}

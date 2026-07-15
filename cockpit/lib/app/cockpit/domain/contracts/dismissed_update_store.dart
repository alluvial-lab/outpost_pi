/// Persist the update version the user **dismissed** by closing its card.
///
/// This domain contract is implemented with Hive in `data/`. The card stays
/// hidden for that version but reappears when a newer version is released.
abstract class DismissedUpdateStore {
  /// Return the last dismissed version, or `null` if none was dismissed.
  String? dismissedVersion();

  /// Mark [version] as dismissed.
  Future<void> dismiss(String version);
}

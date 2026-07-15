/// Describe an external application that can open a directory, such as an IDE or Finder.
class LaunchableApp {
  const LaunchableApp({required this.id, required this.name, this.iconPath});

  /// Stable identifier used to persist the user's last selection.
  ///
  /// Known values are `'cursor'`, `'windsurf'`, `'antigravity'`, `'vscode'`,
  /// and `'finder'`.
  final String id;

  /// Human-readable label displayed in the dropdown.
  final String name;

  /// Path to a 64×64 PNG extracted from the application bundle.
  ///
  /// May be `null` when extraction fails, in which case the widget uses its
  /// fallback Material icon.
  final String? iconPath;
}

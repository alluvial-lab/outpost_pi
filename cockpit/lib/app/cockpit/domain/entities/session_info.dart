/// Describe a saved Pi session stored as `.jsonl` under `~/.pi/agent/sessions/<cwd>/`.
class SessionInfo {
  const SessionInfo({
    required this.path,
    required this.id,
    required this.modifiedAt,
    this.title,
  });

  /// Absolute session-file path used by `switch_session`.
  final String path;

  /// Short session id taken from the file-name suffix.
  final String id;

  /// Last-modified time used for ordering and display.
  final DateTime modifiedAt;

  /// Human-readable label derived from the **first user message** as a chat title.
  ///
  /// Pi does not store session names. This is `null` when no title was requested
  /// (`withTitle: false`) or when the session is empty.
  final String? title;
}

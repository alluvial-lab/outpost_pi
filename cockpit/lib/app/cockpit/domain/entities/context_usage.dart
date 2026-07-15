/// Context-window usage reported by `get_session_stats` (`contextUsage`).
class ContextUsage {
  const ContextUsage({this.tokens, required this.contextWindow, this.percent});

  /// Estimated tokens in the current context; `null` immediately after compaction.
  final int? tokens;

  /// Total context-window size in tokens.
  final int contextWindow;

  /// Percentage used on the **0–100** scale (for example, `0.1578` = 0.16%).
  ///
  /// Remains `null` after compaction until the next assistant response.
  final double? percent;
}

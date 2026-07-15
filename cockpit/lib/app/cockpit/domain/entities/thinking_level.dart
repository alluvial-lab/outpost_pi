/// Represent model reasoning effort for the `set_thinking_level` command.
///
/// The canonical ladder runs from [off] through [xhigh]. [availableFor] derives
/// model support from its `thinkingLevelMap`. The wire always carries the
/// canonical name, which Pi maps to the provider internally.
enum ThinkingLevel {
  off,
  minimal,
  low,
  medium,
  high,
  xhigh;

  /// Canonical string sent on the wire (`{"type":"set_thinking_level","level":"high"}`).
  String get wire => name;

  /// English label displayed to the user.
  String get label => switch (this) {
    ThinkingLevel.off => 'off',
    ThinkingLevel.minimal => 'minimal',
    ThinkingLevel.low => 'low',
    ThinkingLevel.medium => 'medium',
    ThinkingLevel.high => 'high',
    ThinkingLevel.xhigh => 'xhigh',
  };

  static ThinkingLevel fromWire(String? value) =>
      ThinkingLevel.values.firstWhere(
        (level) => level.name == value,
        orElse: () => ThinkingLevel.off,
      );

  /// Return the levels accepted by a model according to `thinkingLevelMap`.
  ///
  /// A level is excluded only when the map contains it with a `null` value.
  /// Missing keys remain available by default, and an empty map enables the
  /// entire ladder.
  static List<ThinkingLevel> availableFor(Map<String, String?> map) {
    if (map.isEmpty) return values;
    return [
      for (final level in values)
        if (!(map.containsKey(level.name) && map[level.name] == null)) level,
    ];
  }
}

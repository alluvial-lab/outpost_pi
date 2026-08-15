/// Record the user's theme-mode choice without importing Flutter into domain.
enum AppThemeMode { system, light, dark }

/// Select the code viewer's syntax theme family across light and dark variants.
enum SyntaxThemeId { one, dracula, github }

/// Represent immutable application preferences persisted locally through Hive.
///
/// Apply changes through [copyWith]. A `null` font selects the design default.
class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.interfaceFont,
    this.interfaceSize = 14,
    this.codeFont,
    this.codeSize = 13,
    this.terminalFont,
    this.syntaxTheme = SyntaxThemeId.one,
    this.pinUserMessage = true,
    this.lastOpenAppId,
    this.lspCommands = const <String, String>{},
    this.lspFormatters = const <String, String>{},
    this.formatOnSave = false,
    this.notificationsEnabled = true,
  });

  final AppThemeMode themeMode;

  /// Interface font family; `null` or empty selects Space Mono.
  final String? interfaceFont;

  /// Base UI size in pixels; styles scale proportionally.
  final double interfaceSize;

  /// Code font family; `null` or empty selects Space Mono.
  final String? codeFont;

  /// Code font size in pixels for the viewer, diff, and terminal.
  final double codeSize;

  /// Terminal font family; `null` or empty selects xterm's default monospace.
  ///
  /// Its size follows [codeSize].
  final String? terminalFont;

  final SyntaxThemeId syntaxTheme;

  /// Keep the user's message pinned above a scrolling response for each turn.
  final bool pinUserMessage;

  /// Identifier of the app most recently used for Open.
  final String? lastOpenAppId;

  /// LSP command override by `languageId`, such as
  /// `'dart' → 'dart language-server'`.
  ///
  /// Empty or absent entries use the catalog default configured under Language.
  final Map<String, String> lspCommands;

  /// External formatter command by `languageId`, with a `%FILE%` placeholder.
  ///
  /// An entry takes precedence over LSP formatting; an empty map uses the LSP.
  final Map<String, String> lspFormatters;

  /// Format automatically when saving with Cmd+S.
  final bool formatOnSave;

  /// Send an OS notification when an agent finishes while the window is unfocused.
  final bool notificationsEnabled;

  AppSettings copyWith({
    AppThemeMode? themeMode,
    String? interfaceFont,
    bool clearInterfaceFont = false,
    double? interfaceSize,
    String? codeFont,
    bool clearCodeFont = false,
    double? codeSize,
    String? terminalFont,
    bool clearTerminalFont = false,
    SyntaxThemeId? syntaxTheme,
    bool? pinUserMessage,
    String? lastOpenAppId,
    Map<String, String>? lspCommands,
    Map<String, String>? lspFormatters,
    bool? formatOnSave,
    bool? notificationsEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      interfaceFont: clearInterfaceFont
          ? null
          : (interfaceFont ?? this.interfaceFont),
      interfaceSize: interfaceSize ?? this.interfaceSize,
      codeFont: clearCodeFont ? null : (codeFont ?? this.codeFont),
      codeSize: codeSize ?? this.codeSize,
      terminalFont: clearTerminalFont
          ? null
          : (terminalFont ?? this.terminalFont),
      syntaxTheme: syntaxTheme ?? this.syntaxTheme,
      pinUserMessage: pinUserMessage ?? this.pinUserMessage,
      lastOpenAppId: lastOpenAppId ?? this.lastOpenAppId,
      lspCommands: lspCommands ?? this.lspCommands,
      lspFormatters: lspFormatters ?? this.lspFormatters,
      formatOnSave: formatOnSave ?? this.formatOnSave,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'themeMode': themeMode.name,
    'interfaceFont': interfaceFont,
    'interfaceSize': interfaceSize,
    'codeFont': codeFont,
    'codeSize': codeSize,
    'terminalFont': terminalFont,
    'syntaxTheme': syntaxTheme.name,
    'pinUserMessage': pinUserMessage,
    if (lastOpenAppId != null) 'lastOpenAppId': lastOpenAppId,
    if (lspCommands.isNotEmpty) 'lspCommands': lspCommands,
    if (lspFormatters.isNotEmpty) 'lspFormatters': lspFormatters,
    if (formatOnSave) 'formatOnSave': true,
    if (!notificationsEnabled) 'notificationsEnabled': false,
  };

  factory AppSettings.fromJson(Map<dynamic, dynamic> json) {
    String? str(Object? v) {
      final s = (v as String?)?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return AppSettings(
      themeMode: _enumByName(
        AppThemeMode.values,
        json['themeMode'],
        AppThemeMode.system,
      ),
      interfaceFont: str(json['interfaceFont']),
      interfaceSize: (json['interfaceSize'] as num?)?.toDouble() ?? 14,
      codeFont: str(json['codeFont']),
      codeSize: (json['codeSize'] as num?)?.toDouble() ?? 13,
      terminalFont: str(json['terminalFont']),
      syntaxTheme: _enumByName(
        SyntaxThemeId.values,
        json['syntaxTheme'],
        SyntaxThemeId.one,
      ),
      pinUserMessage: json['pinUserMessage'] as bool? ?? true,
      lastOpenAppId: str(json['lastOpenAppId']),
      lspCommands: _strMap(json['lspCommands']),
      lspFormatters: _strMap(json['lspFormatters']),
      formatOnSave: json['formatOnSave'] as bool? ?? false,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
    );
  }
}

Map<String, String> _strMap(Object? raw) {
  if (raw is! Map) return const <String, String>{};
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (k is String && v is String && v.trim().isNotEmpty) out[k] = v;
  });
  return out;
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}

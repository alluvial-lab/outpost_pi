import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';

/// Define how to detect and launch a language server.
///
/// Associates file extensions, project-root markers (see [ProjectRootFinder]),
/// and the default language-server command. The command stores the executable
/// and arguments separately because naively splitting a string breaks paths
/// containing spaces.
///
/// In Wave 2, the Language screen overrides `defaultExecutable` and
/// `defaultArgs` from user preferences; PATH detection supplies the default.
class LanguageDef {
  const LanguageDef({
    required this.id,
    required this.label,
    required this.extensions,
    required this.markers,
    required this.defaultExecutable,
    this.defaultArgs = const <String>[],
  });

  /// LSP `languageId` sent in `didOpen` and used as the config/pool key.
  final String id;

  /// Human-readable name for the Language screen.
  final String label;

  /// Lowercase file extensions, without dots, mapped to this language.
  final List<String> extensions;

  /// Project-root marker files, as exact names or `*.suffix` patterns.
  final List<String> markers;

  final String defaultExecutable;
  final List<String> defaultArgs;

  LspServerSpec toSpec({String? executable, List<String>? args}) =>
      LspServerSpec(
        languageId: id,
        executable: executable ?? defaultExecutable,
        args: args ?? defaultArgs,
      );
}

/// Catalog the supported languages.
///
/// Dart is the primary case because its server ships with the Flutter SDK. The
/// others are prepared for Wave 2 configuration and PATH status checks.
const List<LanguageDef> kLanguageDefs = <LanguageDef>[
  LanguageDef(
    id: 'dart',
    label: 'Dart',
    extensions: <String>['dart'],
    markers: <String>['pubspec.yaml'],
    defaultExecutable: 'dart',
    defaultArgs: <String>['language-server', '--client-id', 'cockpit'],
  ),
  LanguageDef(
    id: 'typescript',
    label: 'TypeScript',
    extensions: <String>['ts', 'tsx', 'mts', 'cts'],
    markers: <String>['tsconfig.json', 'package.json'],
    defaultExecutable: 'typescript-language-server',
    defaultArgs: <String>['--stdio'],
  ),
  LanguageDef(
    id: 'javascript',
    label: 'JavaScript',
    extensions: <String>['js', 'jsx', 'mjs', 'cjs'],
    markers: <String>['jsconfig.json', 'package.json'],
    defaultExecutable: 'typescript-language-server',
    defaultArgs: <String>['--stdio'],
  ),
  LanguageDef(
    id: 'python',
    label: 'Python',
    extensions: <String>['py', 'pyi'],
    markers: <String>[
      'pyproject.toml',
      'setup.py',
      'setup.cfg',
      'requirements.txt',
      'Pipfile',
    ],
    defaultExecutable: 'pyright-langserver',
    defaultArgs: <String>['--stdio'],
  ),
  LanguageDef(
    id: 'go',
    label: 'Go',
    extensions: <String>['go'],
    markers: <String>['go.mod', 'go.work'],
    defaultExecutable: 'gopls',
  ),
  LanguageDef(
    id: 'rust',
    label: 'Rust',
    extensions: <String>['rs'],
    markers: <String>['Cargo.toml'],
    defaultExecutable: 'rust-analyzer',
  ),
  LanguageDef(
    id: 'php',
    label: 'PHP',
    extensions: <String>['php'],
    markers: <String>['composer.json'],
    defaultExecutable: 'intelephense',
    defaultArgs: <String>['--stdio'],
  ),
  LanguageDef(
    id: 'csharp',
    label: 'C#',
    extensions: <String>['cs'],
    markers: <String>['*.csproj', '*.sln'],
    defaultExecutable: 'csharp-ls',
  ),
  LanguageDef(
    id: 'java',
    label: 'Java',
    extensions: <String>['java'],
    markers: <String>[
      'pom.xml',
      'build.gradle',
      'build.gradle.kts',
      'settings.gradle',
    ],
    defaultExecutable: 'jdtls',
  ),
];

/// Resolve a [LanguageDef] from a path's extension.
///
/// Returns `null` when no supported language matches.
LanguageDef? languageForPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = path.substring(dot + 1).toLowerCase();
  for (final def in kLanguageDefs) {
    if (def.extensions.contains(ext)) return def;
  }
  return null;
}

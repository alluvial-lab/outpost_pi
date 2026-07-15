import 'dart:io';

/// Find a file's project root by walking up to a language marker.
///
/// Markers include `pubspec.yaml` for Dart and `package.json` or
/// `tsconfig.json` for TypeScript. This resolves monorepo boundaries: for
/// `mono/cockpit/lib/main.dart`, the Dart server root is `mono/cockpit/`, where
/// `pubspec.yaml` lives, rather than `mono/`.
///
/// The pool key is `(language, root)`, so files in one package share a server
/// while distinct packages use distinct servers.
class ProjectRootFinder {
  const ProjectRootFinder();

  /// Walk up from [filePath] looking for any of [markers].
  ///
  /// Markers may be exact names such as `pubspec.yaml` or suffix patterns such
  /// as `*.csproj`. Returns the nearest matching root, or `null` so the caller
  /// can choose a fallback, usually the workspace directory.
  String? findRoot(String filePath, List<String> markers) {
    if (markers.isEmpty) return null;
    var dir = Directory(File(filePath).parent.path);
    // Bound traversal defensively rather than walking an arbitrary tree.
    for (var depth = 0; depth < 64; depth++) {
      if (_hasMarker(dir, markers)) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break; // Reached the filesystem root.
      dir = parent;
    }
    return null;
  }

  bool _hasMarker(Directory dir, List<String> markers) {
    final exact = <String>{};
    final suffixes = <String>[];
    for (final m in markers) {
      if (m.startsWith('*.')) {
        suffixes.add(m.substring(1)); // `.csproj`
      } else {
        exact.add(m);
      }
    }
    // Exact names allow inexpensive direct checks.
    for (final name in exact) {
      if (File('${dir.path}${Platform.pathSeparator}$name').existsSync()) {
        return true;
      }
    }
    // Suffix patterns such as *.csproj/*.sln require listing the directory.
    if (suffixes.isNotEmpty) {
      try {
        for (final entity in dir.listSync(followLinks: false)) {
          if (entity is File) {
            final name = entity.path.split(Platform.pathSeparator).last;
            if (suffixes.any(name.endsWith)) return true;
          }
        }
      } catch (_) {
        // Ignore directories that cannot be read.
      }
    }
    return false;
  }
}

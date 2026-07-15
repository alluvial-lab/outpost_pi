import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/file_searcher.dart';

/// Index folder files with a bounded recursive walk and rank matching paths.
///
/// Skips hidden and expensive directories, and caches each root briefly to
/// avoid walking the disk again for every keystroke.
class FileSearcherImpl implements FileSearcher {
  FileSearcherImpl();

  static const int _maxFiles = 6000;
  static const Duration _ttl = Duration(seconds: 15);

  /// Noisy or expensive directories excluded in addition to hidden `.dir`s.
  static const Set<String> _ignored = <String>{
    'node_modules',
    'build',
    '.dart_tool',
    '.next',
    'dist',
    'out',
    'Pods',
    'DerivedData',
    '.gradle',
    '.venv',
    'venv',
    '__pycache__',
    'target',
    'vendor',
    'coverage',
  };

  final Map<String, _Cache> _cache = <String, _Cache>{};

  @override
  Future<List<String>> search(
    String root,
    String query, {
    int limit = 12,
  }) async {
    final files = await _files(root);
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return files.take(limit).toList();

    final ranked = <_Ranked>[];
    for (final path in files) {
      final lower = path.toLowerCase();
      final base = lower.split('/').last;
      final int score;
      if (base.startsWith(q)) {
        score = 0; // Filename starts with the query.
      } else if (base.contains(q)) {
        score = 1; // Filename contains the query.
      } else if (lower.contains(q)) {
        score = 2; // Full path contains the query.
      } else {
        continue;
      }
      ranked.add(_Ranked(path, score));
    }
    ranked.sort((a, b) {
      if (a.score != b.score) return a.score - b.score;
      return a.path.length - b.path.length; // Prefer shorter paths on a tie.
    });
    return ranked.take(limit).map((r) => r.path).toList();
  }

  Future<List<String>> _files(String root) async {
    final cached = _cache[root];
    if (cached != null && DateTime.now().difference(cached.builtAt) < _ttl) {
      return cached.files;
    }
    final files = await _walk(Directory(root));
    files.sort();
    _cache[root] = _Cache(DateTime.now(), files);
    return files;
  }

  Future<List<String>> _walk(Directory root) async {
    final out = <String>[];
    if (!await root.exists()) return out;
    final rootPath = root.path;
    final stack = <Directory>[root];
    while (stack.isNotEmpty && out.length < _maxFiles) {
      final dir = stack.removeLast();
      final List<FileSystemEntity> entries;
      try {
        entries = await dir.list(followLinks: false).toList();
      } catch (_) {
        continue; // Skip directories that cannot be read.
      }
      for (final entity in entries) {
        final name = entity.path.split('/').last;
        if (entity is Directory) {
          if (name.startsWith('.') || _ignored.contains(name)) continue;
          stack.add(entity);
        } else if (entity is File) {
          if (out.length >= _maxFiles) break;
          final p = entity.path;
          out.add(
            p.startsWith('$rootPath/') ? p.substring(rootPath.length + 1) : p,
          );
        }
      }
    }
    return out;
  }
}

class _Cache {
  _Cache(this.builtAt, this.files);
  final DateTime builtAt;
  final List<String> files;
}

class _Ranked {
  _Ranked(this.path, this.score);
  final String path;
  final int score;
}

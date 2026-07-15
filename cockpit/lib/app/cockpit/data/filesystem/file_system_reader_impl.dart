import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/file_system_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';

/// Read directory children through `dart:io`, with folders sorted before files.
///
/// Includes useful hidden entries such as `.pi`, `.claude`, and `.env`, but
/// excludes VCS directories at every level.
class FileSystemReaderImpl implements FileSystemReader {
  const FileSystemReaderImpl();

  /// Version-control directories hidden throughout the tree, not only at root.
  static const Set<String> _hiddenDirs = <String>{'.git', '.hg', '.svn'};

  @override
  Future<List<FileNode>> children(String dirPath) async {
    if (dirPath.isEmpty) return const <FileNode>[];
    final dir = Directory(dirPath);
    if (!await dir.exists()) return const <FileNode>[];

    final dirs = <FileNode>[];
    final files = <FileNode>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        final name = entity.path.split(Platform.pathSeparator).last;
        final isDir = entity is Directory;
        if (isDir && _hiddenDirs.contains(name)) continue;
        final node = FileNode(
          name: name,
          path: entity.path,
          isDirectory: isDir,
        );
        (isDir ? dirs : files).add(node);
      }
    } on FileSystemException {
      return const <FileNode>[];
    }

    int byName(FileNode a, FileNode b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    dirs.sort(byName);
    files.sort(byName);
    return <FileNode>[...dirs, ...files];
  }
}

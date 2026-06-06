import 'dart:io';

import 'package:cockpit/domain/contracts/file_system_reader.dart';
import 'package:cockpit/domain/entities/file_node.dart';

/// Lê a árvore via `dart:io`: pastas primeiro (ordenadas), depois arquivos,
/// ignorando ocultos (`.git`, `.dart_tool`…).
class FileSystemReaderImpl implements FileSystemReader {
  const FileSystemReaderImpl();

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
        if (name.startsWith('.')) continue;
        final isDir = entity is Directory;
        final node = FileNode(name: name, path: entity.path, isDirectory: isDir);
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

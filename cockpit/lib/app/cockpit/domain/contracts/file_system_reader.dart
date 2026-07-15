import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';

/// Read the file tree without modifying it; the cockpit observes but does not
/// edit through this contract.
///
/// This domain contract is implemented with `dart:io` in `data/filesystem/`.
abstract class FileSystemReader {
  /// Return the immediate, non-hidden children of [dirPath].
  ///
  /// Directories come first and entries are sorted.
  Future<List<FileNode>> children(String dirPath);
}

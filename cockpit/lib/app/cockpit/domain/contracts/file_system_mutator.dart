import 'package:cockpit/app/core/domain/result.dart';

/// Mutate the file tree by creating, renaming, moving, or trashing entries.
///
/// This is the write counterpart to [FileSystemReader]. It is implemented in
/// `data/filesystem/` with `dart:io` and, on macOS, `osascript`. Each operation
/// returns `Result<void, String>` with a UI-ready message on failure.
abstract class FileSystemMutator {
  /// Create an **empty** file at [path].
  ///
  /// Fails when an entry already exists at the path or its parent folder does
  /// not exist.
  Future<Result<void, String>> createFile(String path);

  /// Create a directory at [path], failing when it already exists.
  Future<Result<void, String>> createDirectory(String path);

  /// Rename or move the file or folder at [from] to [to].
  ///
  /// Fails when [to] already exists.
  Future<Result<void, String>> rename(String from, String to);

  /// Move [path] to recoverable trash.
  ///
  /// Uses Finder via `osascript` on macOS and permanently deletes on other
  /// platforms, where confirmation remains the UI's responsibility. The
  /// operation is idempotent: a missing path is successful.
  Future<Result<void, String>> moveToTrash(String path);
}

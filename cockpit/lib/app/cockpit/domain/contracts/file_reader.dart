import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';

/// Read and classify a file for the viewer as markdown, text, image, or
/// unsupported content.
///
/// This domain contract is implemented with `dart:io` in `data/filesystem/`.
abstract class FileReader {
  Future<FileView> read(String path);

  /// Overwrite [path] with UTF-8 [content].
  ///
  /// Returns `true` on success and `false` when I/O fails, such as for denied
  /// permission, a full disk, or a missing path. There is no merge or lock:
  /// concurrent agent writes are last-write-wins in the MVP scope.
  Future<bool> write(String path, String content);

  /// Emit `void` whenever [path] is modified or deleted on disk.
  ///
  /// The viewer uses this long-lived stream to reload content live and must
  /// cancel it when the tab closes. Watch failures are emitted as stream errors
  /// so the owner can surface them instead of silently disabling live reload.
  Stream<void> watch(String path);
}

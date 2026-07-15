import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';

/// Read a folder's Git state.
///
/// This domain contract is implemented in `data/` by running `git`.
abstract class GitStatusReader {
  /// Return [GitInfo] for the repository at [path].
  ///
  /// Returns `null` when the folder is **not** a Git repository or Git is
  /// unavailable.
  Future<GitInfo?> read(String path);
}

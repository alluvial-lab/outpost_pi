import 'package:cockpit/app/core/utils/spawn_directory.dart';

/// Expose the directory selected by a process-spawning gateway.
///
/// This optional capability keeps terminal recovery observable without making
/// test gateways or non-process implementations depend on filesystem details.
abstract interface class TerminalSpawnDirectory {
  SpawnDirectory? get spawnDirectory;
}

/// Run a shell in a native pseudo-terminal (PTY).
///
/// The `data/terminal/` implementation uses `kyroon_pty` with forkpty on
/// macOS/Linux and ConPTY on Windows. `TerminalSession` in `ui/` depends only on
/// this domain interface.
abstract class TerminalGateway {
  /// Start the shell in a PTY rooted at [workingDirectory].
  void start({
    required String workingDirectory,
    int rows = 25,
    int columns = 80,
  });

  /// Emit bytes from the shell's stdout and stderr.
  Stream<List<int>> get output;

  /// Write keyboard input to the shell's stdin.
  void write(List<int> data);

  /// Resize the PTY to [rows] by [columns].
  void resize(int rows, int columns);

  /// Stop the shell cleanly without leaving an orphan process.
  Future<void> kill();
}

import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/core/utils/spawn_directory.dart';
import 'package:kyroon_pty/kyroon_pty.dart';

/// Run the platform's real shell in a native `kyroon_pty` pseudo-terminal.
///
/// This adapter owns the PTY lifecycle and explicitly advertises the terminal
/// capabilities supported by Cockpit's xterm emulator.
class PtyTerminalGateway implements TerminalGateway, TerminalSpawnDirectory {
  Pty? _pty;
  SpawnDirectory? _spawnDirectory;

  @override
  SpawnDirectory? get spawnDirectory => _spawnDirectory;

  @override
  void start({
    required String workingDirectory,
    int rows = 25,
    int columns = 80,
  }) {
    final resolved = resolveSpawnDirectory(workingDirectory);
    _spawnDirectory = resolved;
    _pty = Pty.start(
      _shell(),
      arguments: _shellArgs(),
      workingDirectory: resolved.path.isEmpty ? null : resolved.path,
      environment: _terminalEnv(),
      rows: rows,
      columns: columns,
    );
  }

  @override
  Stream<List<int>> get output =>
      _pty?.output ?? const Stream<List<int>>.empty();

  @override
  void write(List<int> data) =>
      _pty?.write(data is Uint8List ? data : Uint8List.fromList(data));

  @override
  void resize(int rows, int columns) => _pty?.resize(rows, columns);

  @override
  Future<void> kill() async {
    try {
      _pty?.kill();
    } catch (_) {
      // The PTY may already have exited.
    }
  }

  /// Build the PTY environment from the app environment and terminal capabilities.
  ///
  /// - `TERM=xterm-256color` matches the Flutter xterm emulator. Setting it
  ///   explicitly avoids degraded ncurses behavior when a Finder-launched app
  ///   inherits no `TERM` value.
  /// - `COLORTERM=truecolor` advertises the emulator's 24-bit RGB support
  ///   (SGR `38;2;r;g;b`), preventing terminal tools from approximating colors
  ///   with the 256-color palette.
  ///
  /// `kyroon_pty` applies this map last, so these capability declarations
  /// override inherited values.
  Map<String, String> _terminalEnv() => {
    ...Platform.environment,
    'TERM': 'xterm-256color',
    'COLORTERM': 'truecolor',
  };

  /// Select the platform shell.
  String _shell() {
    if (Platform.isWindows) {
      // Keep cmd.exe on Windows ARM, where PowerShell PTY spawning remains
      // unstable. Use powershell.exe by default on other Windows builds.
      if (_isWindowsArm) return Platform.environment['COMSPEC'] ?? 'cmd.exe';
      return 'powershell.exe';
    }
    return Platform.environment['SHELL'] ?? '/bin/zsh';
  }

  /// Select shell arguments that restore the user's expected command environment.
  ///
  /// On macOS and Linux, `-l` starts a login shell like Terminal.app or iTerm.
  /// Finder- and Dock-launched apps otherwise inherit only the minimal system
  /// PATH, and a non-login shell misses `.zprofile`, `/etc/zprofile`,
  /// `path_helper`, Homebrew, Docker, and .NET path setup. The attached TTY also
  /// makes the shell interactive, so `.zshrc` still loads nvm configuration.
  ///
  /// Windows shells inherit the registry PATH even when launched from a GUI,
  /// so they require no flag.
  List<String> _shellArgs() {
    if (Platform.isWindows) return const [];
    return const ['-l'];
  }

  /// Detect Windows ARM from the native build architecture in [Platform.version].
  ///
  /// Unlike `PROCESSOR_ARCHITECTURE`, which can report WOW emulation, the build
  /// marker reliably contains `arm` or `arm64` for a native ARM app.
  bool get _isWindowsArm => Platform.version.toLowerCase().contains('arm');
}

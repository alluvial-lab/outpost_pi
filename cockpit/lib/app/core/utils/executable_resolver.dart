import 'dart:io';

/// Check whether [exec] resolves to an existing executable.
///
/// Absolute paths are checked directly. A bare name is resolved through
/// [resolveExecutable] and is available only when resolution finds a concrete
/// file rather than returning the original name.
Future<bool> isExecutableAvailable(String exec) async {
  final name = exec.trim();
  if (name.isEmpty) return false;
  if (name.contains('/') || name.contains(r'\')) {
    return File(name).existsSync();
  }
  final resolved = await resolveExecutable(name);
  return resolved != name && File(resolved).existsSync();
}

/// Resolve an executable for GUI apps that do not inherit the shell `PATH`.
///
/// On macOS and Linux, checks the user's login shell and then interactive shell
/// before trying [unixCandidates] and [unixHomeRelative] in order. On Windows,
/// uses `where`, then `PATH`/`PATHEXT`, `%APPDATA%\\npm`, and
/// [windowsExtraDirs]. Returns [name] unchanged as the final fallback so the OS
/// can attempt resolution when the caller spawns the process.
Future<String> resolveExecutable(
  String name, {
  List<String> unixCandidates = const [],
  List<String> unixHomeRelative = const [],
  List<String> windowsExtraDirs = const [],
}) async {
  if (Platform.isWindows) {
    final viaWhere = await _windowsWhere(name);
    if (viaWhere != null) return viaWhere;

    // Fall back through PATH×PATHEXT, %APPDATA%\npm, and extra directories.
    final fromPath = await _searchWindowsPath(name);
    if (fromPath != null) return fromPath;
    final appData = Platform.environment['APPDATA'];
    if (appData != null) {
      for (final ext in const ['cmd', 'exe', 'bat']) {
        final shim = '$appData\\npm\\$name.$ext';
        if (await File(shim).exists()) return shim;
      }
    }
    for (final dir in windowsExtraDirs) {
      for (final ext in const ['exe', 'cmd', 'bat']) {
        final candidate = '$dir\\$name.$ext';
        if (await File(candidate).exists()) return candidate;
      }
    }
    return name;
  }

  // On macOS/Linux, run `which` through the login shell for the user's full PATH.
  final viaWhich = await unixWhich(name);
  if (viaWhich != null) return viaWhich;

  // Fall back to known paths.
  for (final candidate in unixCandidates) {
    if (await File(candidate).exists()) return candidate;
  }
  final home = Platform.environment['HOME'];
  if (home != null) {
    for (final rel in unixHomeRelative) {
      final candidate = '$home/$rel';
      if (await File(candidate).exists()) return candidate;
    }
  }
  return name;
}

/// Run `which <name>` in the user's shell to recover npm, nvm, or brew paths.
///
/// Tries a login shell first, loading `.zprofile`, `.bash_profile`, or
/// `.profile` without interactive job-control noise. If unresolved, tries an
/// interactive shell to load `.bashrc` or `.zshrc`, where nvm commonly updates
/// `PATH`. Non-TTY job-control warnings are ignored; only stdout is parsed, so
/// resolution does not depend on the shell exit code.
Future<String?> unixWhich(String name) async {
  final shell = Platform.environment['SHELL'] ?? '/bin/sh';
  return await _runWhich(shell, ['-lc', 'which $name']) ??
      await _runWhich(shell, ['-ic', 'which $name']);
}

/// Return the first existing absolute path printed by `which`.
///
/// Ignores exit code and stderr noise; returns `null` on no match, timeout, or
/// process error.
Future<String?> _runWhich(String shell, List<String> args) async {
  try {
    final res = await Process.run(
      shell,
      args,
    ).timeout(const Duration(seconds: 4));
    for (final line in (res.stdout as String? ?? '').split('\n')) {
      final p = line.trim();
      if (p.startsWith('/') && await File(p).exists()) return p;
    }
  } catch (_) {
    // A missing shell, timeout, or error falls through to the next strategy.
  }
  return null;
}

/// Resolve Windows `PATHEXT` through `where` and return the first existing path.
Future<String?> _windowsWhere(String name) async {
  try {
    final res = await Process.run('where', [
      name,
    ], runInShell: true).timeout(const Duration(seconds: 4));
    if (res.exitCode != 0) return null;
    for (final line in (res.stdout as String? ?? '').split('\n')) {
      final p = line.trim();
      if (p.isNotEmpty && await File(p).exists()) return p;
    }
  } catch (_) {
    // An unavailable `where` or timeout falls through to the other strategies.
  }
  return null;
}

/// Search Windows `PATH` entries using every configured `PATHEXT` suffix.
///
/// Returns the first existing absolute path, or `null` when none match.
Future<String?> _searchWindowsPath(String name) async {
  final pathEnv = Platform.environment['PATH'] ?? '';
  final pathExt = (Platform.environment['PATHEXT'] ?? '.COM;.EXE;.BAT;.CMD')
      .split(';')
      .where((e) => e.isNotEmpty)
      .toList();
  for (final dir in pathEnv.split(';')) {
    if (dir.isEmpty) continue;
    for (final ext in pathExt) {
      final candidate = '$dir\\$name$ext';
      if (await File(candidate).exists()) return candidate;
    }
  }
  return null;
}

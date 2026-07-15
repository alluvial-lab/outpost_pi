import 'dart:io';

import 'package:cockpit/app/core/utils/executable_resolver.dart';
import 'package:cockpit/app/cockpit/domain/contracts/app_launcher.dart';
import 'package:cockpit/app/cockpit/domain/entities/launchable_app.dart';

class _Candidate {
  const _Candidate(this.id, this.name, this.bundle);
  final String id;
  final String name;
  final String bundle;
}

/// macOS candidates in preference order (the first match is the default).
const _kCandidates = [
  _Candidate('cursor', 'Cursor', 'Cursor.app'),
  _Candidate('windsurf', 'Windsurf', 'Windsurf.app'),
  _Candidate('antigravity', 'Antigravity', 'Antigravity.app'),
  _Candidate('vscode', 'Visual Studio Code', 'Visual Studio Code.app'),
];

class _WinCandidate {
  const _WinCandidate(this.id, this.name, this.exeCandidates);
  final String id;
  final String name;

  /// `(envVar, subpath)` pairs whose final path is `%envVar%\<subpath>`.
  ///
  /// The first candidate found on disk resolves the app.
  final List<(String, String)> exeCandidates;
}

/// Windows candidates in preference order.
///
/// IDEs install the `.exe` under `%LOCALAPPDATA%\Programs\…` for per-user
/// installs or under `%ProgramFiles%\…`.
const _kWinCandidates = [
  _WinCandidate('cursor', 'Cursor', [
    ('LOCALAPPDATA', r'Programs\cursor\Cursor.exe'),
  ]),
  _WinCandidate('windsurf', 'Windsurf', [
    ('LOCALAPPDATA', r'Programs\Windsurf\Windsurf.exe'),
  ]),
  _WinCandidate('vscode', 'Visual Studio Code', [
    ('LOCALAPPDATA', r'Programs\Microsoft VS Code\Code.exe'),
    ('ProgramFiles', r'Microsoft VS Code\Code.exe'),
  ]),
];

class _LinuxCandidate {
  const _LinuxCandidate(this.id, this.name, this.command);
  final String id;
  final String name;

  /// CLI command resolved through PATH (`cursor`, `windsurf`, or `code`).
  final String command;
}

/// Linux candidates in preference order.
///
/// IDE packages expose a command on PATH (deb/snap/Flatpak wrapper) that opens
/// the folder as a workspace.
const _kLinuxCandidates = [
  _LinuxCandidate('cursor', 'Cursor', 'cursor'),
  _LinuxCandidate('windsurf', 'Windsurf', 'windsurf'),
  _LinuxCandidate('vscode', 'Visual Studio Code', 'code'),
];

/// Launch external apps for a folder using platform-specific discovery.
///
/// **macOS** probes `/Applications` and extracts icons with `sips`. **Windows**
/// resolves known `.exe` files under `%LOCALAPPDATA%`/`%ProgramFiles%` and uses
/// Explorer as the Finder equivalent. **Linux** resolves IDE commands on PATH
/// and uses `xdg-open` for the default file manager. Outside macOS, the UI uses
/// its Material icon fallback.
class AppLauncherImpl implements AppLauncherGateway {
  const AppLauncherImpl();

  @override
  Future<List<LaunchableApp>> probe() async {
    if (Platform.isMacOS) return _probeMacOS();
    if (Platform.isWindows) return _probeWindows();
    if (Platform.isLinux) return _probeLinux();
    return const <LaunchableApp>[];
  }

  @override
  Future<void> launch(LaunchableApp app, String path) async {
    if (Platform.isWindows) return _launchWindows(app, path);
    if (Platform.isMacOS) return _launchMacOS(app, path);
    if (Platform.isLinux) return _launchLinux(app, path);
  }

  @override
  Future<void> openWithDefaultApp(String path) async {
    if (Platform.isMacOS) {
      // `open <path>` uses the type's default app for a file or Finder for a folder.
      await Process.run('open', [path]);
    } else if (Platform.isLinux) {
      final xdg = await unixWhich('xdg-open') ?? 'xdg-open';
      await Process.run(xdg, [path]);
    } else if (Platform.isWindows) {
      // `start`, a cmd builtin, opens with the default app through ShellExecute.
      // `""` is the required window title when the target may be quoted.
      await Process.run('cmd', ['/c', 'start', '', path]);
    }
  }

  // ---- macOS ----------------------------------------------------------------

  Future<List<LaunchableApp>> _probeMacOS() async {
    final found = <LaunchableApp>[];
    for (final c in _kCandidates) {
      final bundlePath = await _findBundle(c.bundle);
      if (bundlePath != null) {
        final icon = await _extractIcon(bundlePath);
        found.add(LaunchableApp(id: c.id, name: c.name, iconPath: icon));
      }
    }
    // Finder is always available on macOS.
    final finderIcon = await _extractIcon(
      '/System/Library/CoreServices/Finder.app',
    );
    found.add(
      LaunchableApp(id: 'finder', name: 'Finder', iconPath: finderIcon),
    );
    return found;
  }

  Future<void> _launchMacOS(LaunchableApp app, String path) async {
    if (app.id == 'finder') {
      await Process.run('open', [path]);
      return;
    }
    final c = _kCandidates.where((x) => x.id == app.id).firstOrNull;
    if (c == null) return;
    await Process.run('open', ['-a', c.name, path]);
  }

  Future<String?> _findBundle(String bundle) async {
    final home = Platform.environment['HOME'] ?? '';
    for (final base in ['/Applications', '$home/Applications']) {
      final path = '$base/$bundle';
      if (await Directory(path).exists()) return path;
    }
    return null;
  }

  /// Extract the bundle icon into the temporary icon cache.
  ///
  /// Reads `CFBundleIconFile` from Info.plist and uses `sips` to convert the
  /// `.icns` resource to a 32×32 PNG.
  Future<String?> _extractIcon(String bundlePath) async {
    try {
      // Read the icon filename from the plist.
      final plist = await Process.run('defaults', [
        'read',
        '$bundlePath/Contents/Info',
        'CFBundleIconFile',
      ]);
      if (plist.exitCode != 0) return null;
      var iconName = (plist.stdout as String).trim();
      if (iconName.isEmpty) return null;
      if (!iconName.endsWith('.icns')) iconName = '$iconName.icns';

      final icnsPath = '$bundlePath/Contents/Resources/$iconName';
      if (!File(icnsPath).existsSync()) return null;

      // Cache: <temp>/ck_icon_<hash>.png, reused across app launches.
      final cacheKey = icnsPath.hashCode.abs();
      final outPath = '${Directory.systemTemp.path}/ck_icon_$cacheKey.png';
      if (File(outPath).existsSync()) return outPath;

      final sips = await Process.run('sips', [
        '-s',
        'format',
        'png',
        '-z',
        '32',
        '32',
        icnsPath,
        '--out',
        outPath,
      ]);
      return sips.exitCode == 0 ? outPath : null;
    } catch (_) {
      return null;
    }
  }

  // ---- Windows --------------------------------------------------------------

  Future<List<LaunchableApp>> _probeWindows() async {
    final found = <LaunchableApp>[];
    for (final c in _kWinCandidates) {
      if (await _findWindowsExe(c) != null) {
        found.add(LaunchableApp(id: c.id, name: c.name));
      }
    }
    // Explorer is the always-available Windows equivalent of Finder.
    found.add(const LaunchableApp(id: 'explorer', name: 'Explorer'));
    return found;
  }

  Future<void> _launchWindows(LaunchableApp app, String path) async {
    if (app.id == 'explorer') {
      // explorer.exe opens the folder; ignore its exit code because success may return 1.
      await Process.run('explorer', [path]);
      return;
    }
    final c = _kWinCandidates.where((x) => x.id == app.id).firstOrNull;
    if (c == null) return;
    final exe = await _findWindowsExe(c);
    if (exe == null) return;
    // Open the folder as an IDE workspace without tying the process to the app.
    await Process.start(exe, [path], mode: ProcessStartMode.detached);
  }

  /// Resolve the first candidate `.exe` found on disk, or `null`.
  Future<String?> _findWindowsExe(_WinCandidate c) async {
    for (final (envVar, sub) in c.exeCandidates) {
      final base = Platform.environment[envVar];
      if (base == null || base.isEmpty) continue;
      final exe = '$base\\$sub';
      if (await File(exe).exists()) return exe;
    }
    return null;
  }

  // ---- Linux ----------------------------------------------------------------

  Future<List<LaunchableApp>> _probeLinux() async {
    final found = <LaunchableApp>[];
    for (final c in _kLinuxCandidates) {
      if (await unixWhich(c.command) != null) {
        found.add(LaunchableApp(id: c.id, name: c.name));
      }
    }
    // `xdg-open` provides the Finder/Explorer equivalent and is available on
    // nearly every Linux desktop through xdg-utils.
    if (await unixWhich('xdg-open') != null) {
      found.add(const LaunchableApp(id: 'files', name: 'Files'));
    }
    return found;
  }

  Future<void> _launchLinux(LaunchableApp app, String path) async {
    if (app.id == 'files') {
      // Open the folder in the default file manager.
      final xdg = await unixWhich('xdg-open') ?? 'xdg-open';
      await Process.run(xdg, [path]);
      return;
    }
    final c = _kLinuxCandidates.where((x) => x.id == app.id).firstOrNull;
    if (c == null) return;
    final exe = await unixWhich(c.command) ?? c.command;
    // Open the folder as an IDE workspace without tying the process to the app.
    await Process.start(exe, [path], mode: ProcessStartMode.detached);
  }
}

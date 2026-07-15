import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/core/domain/contracts/environment_probe.dart';

/// Detect installed components through the filesystem and `pi --version`.
///
/// All probes are best-effort; any I/O failure is reported as not installed.
class EnvironmentProbeImpl implements EnvironmentProbe {
  EnvironmentProbeImpl(this._config);

  final PiSpawnConfig _config;

  // Windows uses USERPROFILE instead of HOME.
  String? get _home =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  @override
  Future<bool> piInstalled() async {
    final exe = _config.executable;
    // A path resolved at startup, rather than a bare PATH name, only needs to
    // exist. Recognize both Unix (`/`) and Windows (`\`) separators.
    if (exe.contains('/') || exe.contains(r'\')) {
      if (await File(exe).exists()) return true;
    }
    // Try running a bare `pi` resolved through PATH. A macOS GUI app does not
    // inherit the shell PATH, but startup candidate paths should already have
    // found such installs. `runInShell` lets Windows resolve npm `.cmd`/`.bat`
    // shims through PATHEXT. This remains best-effort.
    try {
      final result = await Process.run(exe, const [
        '--version',
      ], runInShell: true);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> extensionInstalled() async {
    final home = _home;
    if (home == null) return false;
    try {
      final file = File('$home/.pi/agent/settings.json');
      if (!await file.exists()) return false;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return false;
      final packages = json['packages'];
      if (packages is! List) return false;
      // Match production specs (`npm:outpost-pi` / `outpost-pi`) and local
      // development paths ending in `pi-extension`.
      return packages.whereType<String>().any((p) {
        final low = p.toLowerCase();
        return low.contains('outpost-pi') || low.endsWith('pi-extension');
      });
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> supervisorInstalled() async {
    final home = _home;
    if (home == null) return false;
    try {
      // Primary signal: the service was installed by `outpost-pi install`.
      if (Platform.isMacOS) {
        final plist = File(
          '$home/Library/LaunchAgents/dev.outpostpi.supervisord.plist',
        );
        if (await plist.exists()) return true;
      } else if (Platform.isLinux) {
        final unit = File(
          '$home/.config/systemd/user/outpost-pi-supervisord.service',
        );
        if (await unit.exists()) return true;
      } else if (Platform.isWindows) {
        // On Windows, the supervisor runs as the `OutpostPiSupervisor`
        // Scheduled Task created by `outpost-pi install`. The task is the source
        // of truth because it survives reboot and deletion of the .vbs file.
        // Querying needs no elevation; only /Create did.
        try {
          final task = await Process.run('schtasks', const [
            '/Query',
            '/TN',
            'OutpostPiSupervisor',
          ], runInShell: true);
          if (task.exitCode == 0) return true;
        } catch (_) {
          // Fall back to the file check when schtasks is unavailable.
        }
        // Secondary signal: the VBS launcher written under ~/.pi/remote/.
        final vbs = File('$home/.pi/remote/OutpostPiSupervisorLauncher.vbs');
        return vbs.exists();
      }
      // Fallback: look for the binary in known user installation prefixes.
      const candidates = <String>[
        '/opt/homebrew/bin/pi-supervisord',
        '/usr/local/bin/pi-supervisord',
      ];
      for (final candidate in candidates) {
        if (await File(candidate).exists()) return true;
      }
      final local = '$home/.local/bin/pi-supervisord';
      return File(local).exists();
    } catch (_) {
      return false;
    }
  }
}

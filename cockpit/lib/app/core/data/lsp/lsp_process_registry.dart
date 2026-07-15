import 'dart:io';

/// Persist the PIDs of active language-server processes.
///
/// As with [PiProcessRegistry], a hot restart or app crash does not kill child
/// processes created by [Process.start], leaving `dart language-server`,
/// `jdtls`, `node`, and similar processes orphaned. Unlike pi, these servers use
/// several executable names, so `pgrep -x <name>` cannot identify all of them.
/// The registry file is therefore the sole source: every spawned PID is stored,
/// and remaining processes are killed and the file cleared at startup.
class LspProcessRegistry {
  LspProcessRegistry._();

  static String get _path {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.pi/cockpit/lsp-pids';
  }

  /// Kill PIDs left by the previous app lifecycle and clear the registry.
  ///
  /// Call exactly once per startup, before spawning any language server.
  static Future<void> cleanOrphans() async {
    try {
      final file = File(_path);
      if (!await file.exists()) return;
      final pids = (await file.readAsLines())
          .map((l) => int.tryParse(l.trim()))
          .whereType<int>();
      await file.delete();
      for (final p in pids) {
        try {
          Process.killPid(p, ProcessSignal.sigkill);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Record [pid] immediately after a successful spawn.
  static Future<void> register(int pid) async {
    try {
      final file = File(_path);
      await file.parent.create(recursive: true);
      await file.writeAsString('$pid\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// Remove [pid] after a clean server exit.
  static Future<void> unregister(int pid) async {
    try {
      final file = File(_path);
      if (!await file.exists()) return;
      final kept = (await file.readAsLines())
          .where((l) => l.trim() != '$pid')
          .toList();
      if (kept.isEmpty) {
        await file.delete();
      } else {
        await file.writeAsString('${kept.join('\n')}\n');
      }
    } catch (_) {}
  }
}

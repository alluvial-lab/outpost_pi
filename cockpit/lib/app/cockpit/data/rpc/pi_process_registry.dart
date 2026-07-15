import 'dart:io';

/// Persist the PIDs of active `pi --mode rpc` processes for orphan cleanup.
///
/// A `flutter run` hot restart replaces the Dart isolate without killing child
/// processes created by `Process.start`. On boot, [cleanOrphans] combines two
/// cleanup sources:
///
/// 1. The file registry records successful spawns through [register] and
///    removes clean exits through [unregister]. It covers cold restarts and
///    crashes where Cockpit died and the recorded PIDs are no longer children.
/// 2. A PPID scan finds direct `pi` children of the still-running Cockpit
///    process that survived an isolate hot restart.
///
/// Both paths use SIGKILL without waiting, which is appropriate for abandoned
/// development processes. Normal production shutdown remains the gateway's
/// graceful `dispose` and `kill` path.
class PiProcessRegistry {
  PiProcessRegistry._();

  static String get _path {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.pi/cockpit/agent-pids';
  }

  /// Kill Pi orphans from the previous lifecycle and clear the registry.
  ///
  /// Call exactly once per boot, before any new process is spawned.
  static Future<void> cleanOrphans() async {
    // Run both searches concurrently to minimize boot latency.
    final results = await Future.wait([
      _pidsFromRegistry(),
      _orphanedPiChildren(),
    ]);
    final toKill = <int>{...results[0], ...results[1]};
    for (final p in toKill) {
      try {
        Process.killPid(p, ProcessSignal.sigkill); // Immediate and race-free.
      } catch (_) {}
    }
  }

  /// Read registered PIDs and delete the registry file.
  ///
  /// This covers cold restarts and crashes where the parent process died.
  static Future<List<int>> _pidsFromRegistry() async {
    try {
      final file = File(_path);
      if (!await file.exists()) return const <int>[];
      final pids = (await file.readAsLines())
          .map((l) => int.tryParse(l.trim()))
          .whereType<int>()
          .toList();
      await file.delete();
      return pids;
    } catch (_) {
      return const <int>[];
    }
  }

  /// Find processes named exactly `pi` whose PPID is this Cockpit process.
  ///
  /// These are hot-restart orphans: Dart replaced the isolate while the native
  /// Cockpit process and its children survived.
  static Future<List<int>> _orphanedPiChildren() async {
    if (!Platform.isMacOS && !Platform.isLinux) return const <int>[];
    try {
      // `pgrep -x pi` selects only processes named exactly "pi".
      final pgrepResult = await Process.run('pgrep', ['-x', 'pi']);
      final stdout = (pgrepResult.stdout as String).trim();
      if (stdout.isEmpty) return const <int>[];

      final myCockpitPid = pid; // dart:io PID of this native app process.
      final piPids = stdout
          .split('\n')
          .map((l) => int.tryParse(l.trim()))
          .whereType<int>()
          .toList();

      // Include only Pi processes that are direct children of this process.
      final orphans = <int>[];
      for (final piPid in piPids) {
        final psResult = await Process.run('ps', [
          '-o',
          'ppid=',
          '-p',
          '$piPid',
        ]);
        if (psResult.exitCode != 0) continue;
        final ppid = int.tryParse((psResult.stdout as String).trim());
        if (ppid == myCockpitPid) orphans.add(piPid);
      }
      return orphans;
    } catch (_) {
      return const <int>[];
    }
  }

  /// Record [pid] immediately after a successful spawn.
  static Future<void> register(int pid) async {
    try {
      final file = File(_path);
      await file.parent.create(recursive: true);
      await file.writeAsString('$pid\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// Remove [pid] from the registry after a clean process exit.
  static Future<void> unregister(int pid) async {
    try {
      final file = File(_path);
      if (!await file.exists()) return;
      final lines = await file.readAsLines();
      final kept = lines.where((l) => l.trim() != '$pid').toList();
      if (kept.isEmpty) {
        await file.delete();
      } else {
        await file.writeAsString('${kept.join('\n')}\n');
      }
    } catch (_) {}
  }
}

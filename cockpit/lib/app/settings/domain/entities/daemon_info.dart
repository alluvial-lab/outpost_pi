/// Describe a daemon state observed by the supervisor.
enum DaemonState { running, stopped, starting, crashed, unknown }

/// Decode a supervisor daemon state without rejecting future wire values.
///
/// Unknown or absent values map to [DaemonState.unknown].
DaemonState daemonStateFromWire(String? raw) => switch (raw) {
  'running' => DaemonState.running,
  'stopped' => DaemonState.stopped,
  'starting' => DaemonState.starting,
  'crashed' => DaemonState.crashed,
  _ => DaemonState.unknown,
};

/// Represent an always-on `pi --mode rpc` agent managed by `pi-supervisord`.
///
/// Mirrors Outpost-Pi's control-protocol `DaemonInfo` in
/// `pi-extension/src/daemon/control_protocol.ts`. The ID is derived from the
/// working directory (`sha256[0..8]`); `name` and `cwd` come from the registry
/// and local configuration.
class DaemonInfo {
  const DaemonInfo({
    required this.id,
    required this.cwd,
    required this.name,
    required this.state,
    this.pid,
    this.uptimeSeconds,
    this.restartCount,
  });

  final String id;
  final String cwd;
  final String name;
  final DaemonState state;
  final int? pid;
  final int? uptimeSeconds;
  final int? restartCount;

  @override
  bool operator ==(Object other) =>
      other is DaemonInfo &&
      other.id == id &&
      other.cwd == cwd &&
      other.name == name &&
      other.state == state &&
      other.pid == pid &&
      other.uptimeSeconds == uptimeSeconds &&
      other.restartCount == restartCount;

  @override
  int get hashCode =>
      Object.hash(id, cwd, name, state, pid, uptimeSeconds, restartCount);
}

import 'package:cockpit/app/settings/domain/entities/daemon_info.dart';
import 'package:cockpit/app/settings/domain/exceptions/daemon_error.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Control always-on daemon agents managed by `pi-supervisord`.
///
/// Lists and controls daemons through the supervisor UDS at
/// `~/.pi/remote/supervisor.sock`. Creation delegates to `outpost-pi create`,
/// which writes local configuration, registers the daemon, and starts it. The
/// domain owns this contract; socket and process adapters live in `data/`.
///
/// Per-daemon `stop` and `restart` depend on their corresponding supervisor
/// operations and fail with "unknown op" when those operations are unavailable.
abstract class DaemonSupervisor {
  /// Check whether the supervisor socket exists and accepts a connection.
  Future<bool> isOnline();

  /// List registered daemons with their observed runtime state.
  Future<Result<List<DaemonInfo>, DaemonError>> list();

  /// Start one registered daemon by identifier.
  ///
  /// Returns a typed supervisor failure when the action cannot be completed.
  Future<Result<void, DaemonError>> start(String id);

  /// Stop one registered daemon by identifier.
  ///
  /// Returns a typed supervisor failure when the action cannot be completed.
  Future<Result<void, DaemonError>> stop(String id);

  /// Restart one registered daemon by identifier.
  ///
  /// Returns a typed supervisor failure when the action cannot be completed.
  Future<Result<void, DaemonError>> restart(String id);

  /// Start every daemon registered with the supervisor.
  ///
  /// Returns a typed supervisor failure if the fleet action fails.
  Future<Result<void, DaemonError>> startAll();

  /// Stop every daemon registered with the supervisor.
  ///
  /// Returns a typed supervisor failure if the fleet action fails.
  Future<Result<void, DaemonError>> stopAll();

  /// Restart every daemon registered with the supervisor.
  ///
  /// Returns a typed supervisor failure if the fleet action fails.
  Future<Result<void, DaemonError>> restartAll();

  /// Stop and remove a daemon from the registry.
  Future<Result<void, DaemonError>> unregister(String id);

  /// Register and start a daemon for [cwd] via `outpost-pi create`.
  Future<Result<void, DaemonError>> create(String cwd, {String? name});

  /// Rename an agent in the authoritative global daemon registry.
  ///
  /// Updates `name` in `~/.pi/remote/daemons.json`; a running process observes
  /// the new name only after restart because the supervisor injects it at spawn.
  Future<Result<void, DaemonError>> setAgentName(String cwd, String name);

  /// Restart the `pi-supervisord` process rather than an individual daemon.
  ///
  /// Delegates to `outpost-pi restart-supervisor` so the platform-specific
  /// launchctl, systemd, or Windows service path can reload extension code.
  /// Restarting the supervisor also restarts all managed daemons.
  Future<Result<void, DaemonError>> restartSupervisor();
}

import 'package:cockpit/app/core/domain/contracts/environment_probe.dart';
import 'package:flutter/foundation.dart';

/// Decide whether environment-dependent Settings tabs are visible.
///
/// Connectivity, Daemon Agents, and Schedules stay hidden until the outpost-pi
/// extension and supervisor are installed through the agent-tab checklist.
/// This page-scoped gate is created with Settings and runs [check] in `initState`.
class SettingsEnvGate extends ChangeNotifier {
  SettingsEnvGate(this._env);

  final EnvironmentProbe _env;

  bool _remoteReady = false;
  bool _disposed = false;

  /// Report whether both the outpost-pi extension and supervisor are installed.
  bool get remoteReady => _remoteReady;

  /// Probe the environment after mount or an in-place installation.
  Future<void> check() async {
    final extension = await _env.extensionInstalled();
    final supervisor = await _env.supervisorInstalled();
    final next = extension && supervisor;
    if (next == _remoteReady) return;
    _remoteReady = next;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

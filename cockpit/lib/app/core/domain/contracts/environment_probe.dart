/// Probe the user's environment for onboarding prerequisites.
///
/// Checks the Pi binary, the outpost-pi extension registration, and the
/// operating-system supervisor service. Infrastructure probing lives in
/// `data/`; this contract keeps onboarding independent of process and file I/O.
abstract class EnvironmentProbe {
  /// Check whether the `pi` binary is installed and accessible.
  Future<bool> piInstalled();

  /// Check whether `outpost-pi` is registered in `~/.pi/agent/settings.json`.
  Future<bool> extensionInstalled();

  /// Check whether `pi-supervisord` is installed as an OS service.
  Future<bool> supervisorInstalled();
}

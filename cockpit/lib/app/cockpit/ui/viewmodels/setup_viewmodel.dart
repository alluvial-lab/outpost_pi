import 'package:cockpit/app/cockpit/domain/contracts/environment_installer.dart';
import 'package:cockpit/app/cockpit/domain/entities/install_result.dart';
import 'package:cockpit/app/core/domain/contracts/environment_probe.dart';
import 'package:cockpit/app/core/domain/entities/setup_check.dart';
import 'package:flutter/foundation.dart';

/// Coordinate agent-environment checks and installation actions.
///
/// [agentReady] gates agent creation until Pi, the Outpost-Pi extension, and
/// the supervisor are satisfied; `notApplicable` counts as satisfied. Checks
/// run on demand when the user opens an agent tab, rather than during app boot.
class SetupViewModel extends ChangeNotifier {
  SetupViewModel(this._env, this._installer);

  final EnvironmentProbe _env;
  final EnvironmentInstaller _installer;

  CheckStatus pi = CheckStatus.checking;
  CheckStatus extension = CheckStatus.checking;
  CheckStatus supervisor = CheckStatus.checking;

  bool _disposed = false;

  /// Enable agent creation once all three environment checks are satisfied.
  bool get agentReady =>
      pi.satisfied && extension.satisfied && supervisor.satisfied;

  /// Recheck all agent prerequisites concurrently when the checklist opens.
  Future<void> recheckAll() async {
    await Future.wait([recheckPi(), recheckExtension(), recheckSupervisor()]);
  }

  /// Recheck whether the Pi executable is installed.
  Future<void> recheckPi() => _run(
    (s) => pi = s,
    () async => await _env.piInstalled() ? CheckStatus.ok : CheckStatus.missing,
  );

  /// Recheck whether the Outpost-Pi extension is installed.
  Future<void> recheckExtension() => _run(
    (s) => extension = s,
    () async =>
        await _env.extensionInstalled() ? CheckStatus.ok : CheckStatus.missing,
  );

  /// Recheck whether the supervisor is installed.
  Future<void> recheckSupervisor() => _run(
    (s) => supervisor = s,
    () async =>
        await _env.supervisorInstalled() ? CheckStatus.ok : CheckStatus.missing,
  );

  /// Install the Outpost-Pi extension and refresh dependent checks.
  ///
  /// A successful install rechecks both the extension and the supervisor.
  Future<InstallResult> installExtension() async {
    final result = await _installer.installExtension();
    if (result.ok) {
      await recheckExtension();
      await recheckSupervisor();
    }
    return result;
  }

  /// Install the supervisor through Node and recheck it on success.
  Future<InstallResult> installSupervisor() async {
    final result = await _installer.installSupervisor();
    if (result.ok) await recheckSupervisor();
    return result;
  }

  /// Mark a step as checking, run [probe], and publish its resulting status.
  Future<void> _run(
    void Function(CheckStatus) set,
    Future<CheckStatus> Function() probe,
  ) async {
    set(CheckStatus.checking);
    _safeNotify();
    final result = await probe();
    set(result);
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

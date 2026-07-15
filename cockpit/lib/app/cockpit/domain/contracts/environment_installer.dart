import 'package:cockpit/app/cockpit/domain/entities/install_result.dart';

/// Run the onboarding installations: the `outpost-pi` Pi extension and the
/// supervisor OS service.
///
/// This domain contract is implemented with Process in `data/`. Every operation
/// is best-effort: an I/O failure becomes [InstallResult.failure].
abstract class EnvironmentInstaller {
  /// Run `pi install npm:outpost-pi` to register the extension with Pi.
  Future<InstallResult> installExtension();

  /// Run `node <outpost-pi>/dist/index.js install` to install the supervisor.
  ///
  /// Requires the extension to be installed because it provides `index.js`.
  Future<InstallResult> installSupervisor();
}

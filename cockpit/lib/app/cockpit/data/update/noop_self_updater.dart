import 'package:cockpit/app/cockpit/domain/contracts/self_updater.dart';

/// Disable native self-updates on unsupported platforms such as Linux.
///
/// Reports [isSupported] as `false` and otherwise performs no work, allowing
/// `UpdateViewModel` to notify through its manual-download path (`UpdateChecker`
/// reads `latest.json` and opens the artifact URL).
class NoopSelfUpdater implements SelfUpdater {
  const NoopSelfUpdater();

  @override
  bool get isSupported => false;

  @override
  SelfUpdateState get state => const SelfUpdateState.idle();

  @override
  Stream<SelfUpdateState> get changes => const Stream<SelfUpdateState>.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> checkForUpdates({bool inBackground = true}) async {}

  @override
  Future<void> applyDownloadedUpdate() async {}

  @override
  void dispose() {}
}

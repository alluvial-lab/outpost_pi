/// Send native OS notifications through a domain-owned contract.
///
/// The plugin implementation lives in `data/notifications/`.
abstract class Notifier {
  /// Initialize the backend and request permission at startup.
  Future<void> init();

  /// Notify the user that an agent finished a turn.
  Future<void> agentFinished({
    required String agentName,
    required String workspace,
  });
}

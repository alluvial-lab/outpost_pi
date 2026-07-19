/// Resolve endpoints injected by `e2e/run-pairing.sh`.
final class HarnessEndpoints {
  const HarnessEndpoints({
    required this.piHost,
    required this.relay,
    required this.toxiproxy,
  });

  factory HarnessEndpoints.fromEnvironment() {
    final piHost = Uri.parse(
      const String.fromEnvironment('E2E_PI_HOST_URL'),
    );
    final relay = Uri.parse(const String.fromEnvironment('E2E_RELAY_URL'));
    final toxiproxy = Uri.parse(
      const String.fromEnvironment('E2E_TOXIPROXY_URL'),
    );
    if (!piHost.hasScheme || !relay.hasScheme || !toxiproxy.hasScheme) {
      throw StateError('pairing e2e endpoints were not provided by the runner');
    }
    return HarnessEndpoints(
      piHost: piHost,
      relay: relay,
      toxiproxy: toxiproxy,
    );
  }

  final Uri piHost;
  final Uri relay;
  final Uri toxiproxy;
}

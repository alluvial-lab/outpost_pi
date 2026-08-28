import 'package:app/domain/value_objects/reachability.dart';

/// Pure app-side reachability runtime used by transport adapters.
///
/// This object owns only contract state and counters. Sockets, timers, storage,
/// and UI remain owned by [ConnectionManager] or higher layers so the canonical
/// reachability policy can move to generated protocol code later without
/// carrying app infrastructure with it.
final class ReachabilityAdapter {
  ReachabilityState _state = ReachabilityState.offline;
  int _retryAttempt = 0;
  int _missedPings = 0;
  bool _connectInFlight = false;
  int _consecutiveFailureCount = 0;
  ReachabilityFailureKind? _failureKind;
  DateTime? _lastAttemptAt;
  DateTime? _nextRetryAt;

  ReachabilityState get state => _state;
  int get retryAttempt => _retryAttempt;
  int get missedPings => _missedPings;
  bool get connectInFlight => _connectInFlight;
  int get consecutiveFailureCount => _consecutiveFailureCount;
  ReachabilityFailureKind get failureKind =>
      _failureKind ?? ReachabilityFailureKind.unknown;
  DateTime? get lastAttemptAt => _lastAttemptAt;
  DateTime? get nextRetryAt => _nextRetryAt;
  Duration get nextRetryDelay => reachabilityBackoffForAttempt(_retryAttempt);
  bool get waitingForRetry => _state == ReachabilityState.retrying;

  void onConnectRequested({DateTime? at}) {
    _lastAttemptAt = at ?? DateTime.now();
    _nextRetryAt = null;
    _state = ReachabilityState.connecting;
    _connectInFlight = true;
  }

  /// The relay WebSocket factory succeeded and this app has a live socket.
  ///
  /// This is intentionally NOT proof that the Pi-side room is alive. Keep the
  /// retry backoff attempt intact until [onAppFrameObserved] sees real inbound
  /// app/Pi traffic; otherwise a relay that accepts sockets while the Pi is
  /// down pins reconnects back to the 1s floor.
  void onRelayConnectionEstablished() {
    _state = ReachabilityState.online;
    _nextRetryAt = null;
    _missedPings = 0;
    _connectInFlight = false;
  }

  void onConnectFailedRetryable({
    DateTime? at,
    ReachabilityFailureKind failureKind = ReachabilityFailureKind.unknown,
  }) {
    final now = at ?? DateTime.now();
    // A channel can be lost after it was adopted without a local connect
    // start. Record the retry-triggering failure as the latest attempt too.
    _lastAttemptAt = now;
    if (_failureKind == failureKind) {
      _consecutiveFailureCount++;
    } else {
      _failureKind = failureKind;
      _consecutiveFailureCount = 1;
    }
    _nextRetryAt = now.add(nextRetryDelay);
    _state = ReachabilityState.retrying;
    _connectInFlight = false;
  }

  /// Re-arm a missing retry timer without counting another failure.
  void refreshRetryDeadline({DateTime? at}) {
    _nextRetryAt = (at ?? DateTime.now()).add(nextRetryDelay);
    _state = ReachabilityState.retrying;
    _connectInFlight = false;
  }

  void onTransportClosed() {
    _state = ReachabilityState.retrying;
    _missedPings = 0;
    _connectInFlight = false;
  }

  void onAppFrameObserved() {
    _state = ReachabilityState.online;
    _retryAttempt = 0;
    _consecutiveFailureCount = 0;
    _failureKind = null;
    _lastAttemptAt = null;
    _nextRetryAt = null;
    _missedPings = 0;
  }

  void onPingMissed() {
    _missedPings += 1;
    if (_missedPings >= reachabilityHeartbeat.degradedAfterMissedAppPongs) {
      _state = ReachabilityState.degraded;
    }
  }

  void onRetryTimerFired() {
    _retryAttempt += 1;
    _nextRetryAt = null;
    _state = ReachabilityState.connecting;
    _connectInFlight = true;
  }

  void onStopRequested() {
    _state = ReachabilityState.offline;
    _retryAttempt = 0;
    _consecutiveFailureCount = 0;
    _failureKind = null;
    _lastAttemptAt = null;
    _nextRetryAt = null;
    _missedPings = 0;
    _connectInFlight = false;
  }

  void reset() {
    _state = ReachabilityState.offline;
    _retryAttempt = 0;
    _consecutiveFailureCount = 0;
    _failureKind = null;
    _lastAttemptAt = null;
    _nextRetryAt = null;
    _missedPings = 0;
    _connectInFlight = false;
  }
}

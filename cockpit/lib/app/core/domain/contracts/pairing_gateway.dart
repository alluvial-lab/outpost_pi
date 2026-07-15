import 'package:cockpit/app/core/domain/entities/pair_event.dart';

/// Run one ephemeral device-pairing session.
///
/// Starts `pi --mode rpc --no-session` with outpost-pi, injects a pairing
/// `OUTPOST_PI_DIRECT_CONFIG`, and invokes `/outpost-pi pair`. Custom events
/// arrive as typed values through [events]; [cancel] stops the process and
/// removes its temporary directory.
///
/// Each instance owns one pairing attempt and its process. Process and file
/// system details remain in the `data/` adapter.
abstract class PairingGateway {
  /// Broadcast pairing events and close the stream when the session ends.
  Stream<PairEvent> get events;

  /// Start pairing with validity period [ttl].
  ///
  /// Reports startup and session failures as [PairFailed] events rather than
  /// throwing them to the caller.
  Future<void> start({Duration ttl});

  /// End the session, stop its process, and remove its temporary directory.
  Future<void> cancel();
}

/// Create [PairingGateway] instances through a named, injectable factory.
///
/// The named contract lets `ConnectivityViewModel` use `.new` injection because
/// `auto_injector` cannot parse consecutive `T Function()` dependencies.
abstract class PairingGatewayFactory {
  /// Create a fresh gateway for one ephemeral pairing attempt.
  ///
  /// The caller owns cancellation of the returned gateway and its process.
  PairingGateway create();
}

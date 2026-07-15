import 'package:cockpit/app/core/domain/exceptions/relay_error.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Revoke a paired device through `pi --mode rpc`, not the outpost-pi CLI.
///
/// Starts an ephemeral Pi process with outpost-pi and sends
/// `/outpost-pi revoke <shortId>`, which connects the relay and removes the
/// peer. A `Revoked: …` notification confirms success; warnings become
/// [RelayError] values. The process adapter lives in `data/`.
abstract class RevokeGateway {
  /// Revoke the device identified by [shortId] within [timeout].
  ///
  /// Returns [Success] after the confirmation notification, or [Failure] with
  /// a [RelayError] when startup, relay feedback, process exit, or timeout
  /// prevents confirmation. The ephemeral process is torn down before return.
  Future<Result<void, RelayError>> revoke(String shortId, {Duration timeout});
}

/// Create [RevokeGateway] instances through a named, injectable factory.
///
/// The named contract supports `.new` injection into `ConnectivityViewModel`.
abstract class RevokeGatewayFactory {
  /// Create a fresh gateway for one ephemeral revoke operation.
  ///
  /// Each returned gateway starts and tears down its own Pi process when
  /// [RevokeGateway.revoke] runs.
  RevokeGateway create();
}

import 'package:cockpit/app/settings/domain/entities/paired_device.dart';
import 'package:cockpit/app/core/domain/exceptions/relay_error.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Manage Cockpit connectivity through the global relay configuration.
///
/// Delegates to the `outpost-pi` binary and shared
/// `~/.pi/remote/config.json`; Cockpit never implements cryptography or speaks
/// the relay protocol directly. The domain owns this contract, while process
/// and filesystem adapters live in `data/`.
///
/// This boundary covers the global relay and paired-device listing. Pairing and
/// revocation run through `pi --mode rpc` via [PairingGateway] and
/// [RevokeGateway], outside this contract.
abstract class RelayGateway {
  /// Read the relay URL configured in `~/.pi/remote/config.json`.
  ///
  /// A successful `null` result means no relay is configured.
  Future<Result<String?, RelayError>> currentRelay();

  /// Set the global relay URL through `outpost-pi set-relay <url>`.
  Future<Result<void, RelayError>> setRelay(String url);

  /// List paired devices through `outpost-pi devices`.
  Future<Result<List<PairedDevice>, RelayError>> listDevices();

  /// Check whether [url] responds to `GET <url>/health` with HTTP 200.
  ///
  /// Success means healthy; [RelayError] reports why the relay is unreachable.
  Future<Result<void, RelayError>> checkHealth(String url);
}

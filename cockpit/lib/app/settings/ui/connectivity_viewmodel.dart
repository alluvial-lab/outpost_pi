import 'package:cockpit/app/core/domain/contracts/pairing_gateway.dart';
import 'package:cockpit/app/settings/domain/contracts/relay_gateway.dart';
import 'package:cockpit/app/core/domain/contracts/revoke_gateway.dart';
import 'package:cockpit/app/settings/domain/entities/paired_device.dart';
import 'package:cockpit/app/settings/ui/pairing_controller.dart';
import 'package:cockpit/app/settings/ui/revoke_controller.dart';
import 'package:flutter/foundation.dart';

/// Describe the loading state of a Connectivity section.
enum ConnLoad { idle, loading, ready, error }

/// Describe the result of checking relay health via `GET /health`.
enum HealthState { unknown, checking, healthy, unhealthy }

/// Manage the Settings **Connectivity** tab's relay and paired-device state.
///
/// Reads and updates the global relay and lists devices through [RelayGateway].
/// Pairing and revocation dialogs each create their own ephemeral `pi --mode rpc`
/// gateway through [PairingGatewayFactory] or [RevokeGatewayFactory].
class ConnectivityViewModel extends ChangeNotifier {
  ConnectivityViewModel(this._relay, this._pairingFactory, this._revokeFactory);

  final RelayGateway _relay;
  final PairingGatewayFactory _pairingFactory;
  final RevokeGatewayFactory _revokeFactory;

  /// Create a pairing-dialog controller that owns a fresh ephemeral process.
  PairingController newPairingController() =>
      PairingController(_pairingFactory.create);

  /// Create a fresh controller for one revocation dialog.
  RevokeController newRevokeController() =>
      RevokeController(_revokeFactory.create());

  // ---- relay ----------------------------------------------------------------
  ConnLoad relayLoad = ConnLoad.idle;
  String? relayUrl;
  String? relayError;
  bool savingRelay = false;

  // Relay health (`GET /health`).
  HealthState healthState = HealthState.unknown;
  String? healthMessage;

  // ---- devices ---------------------------------------------------------------
  ConnLoad devicesLoad = ConnLoad.idle;
  List<PairedDevice> devices = const <PairedDevice>[];
  String? devicesError;

  bool _disposed = false;

  /// Load relay and device state in parallel when the tab opens.
  Future<void> load() =>
      Future.wait(<Future<void>>[loadRelay(), loadDevices()]);

  /// Load the configured relay into its independent loading or error state.
  ///
  /// Listener notifications are suppressed if this ViewModel is disposed while
  /// the gateway request is pending.
  Future<void> loadRelay() async {
    relayLoad = ConnLoad.loading;
    relayError = null;
    _notify();
    final result = await _relay.currentRelay();
    result.fold(
      (url) {
        relayUrl = url;
        relayLoad = ConnLoad.ready;
      },
      (error) {
        relayError = error.message;
        relayLoad = ConnLoad.error;
      },
    );
    _notify();
  }

  /// Save the relay URL and report whether the update succeeded.
  ///
  /// A successful update lets the view clear its dirty state.
  Future<bool> setRelay(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed == relayUrl) return false;
    savingRelay = true;
    relayError = null;
    _notify();
    final result = await _relay.setRelay(trimmed);
    final ok = result.fold((_) => true, (error) {
      relayError = error.message;
      return false;
    });
    if (ok) {
      relayUrl = trimmed;
      // The previous health check applied to a different URL.
      healthState = HealthState.unknown;
      healthMessage = null;
    }
    savingRelay = false;
    _notify();
    return ok;
  }

  /// Check whether the relay at [url] responds to `GET /health`.
  Future<void> checkRelay(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      healthState = HealthState.unhealthy;
      healthMessage = 'Set the relay URL first.';
      _notify();
      return;
    }
    healthState = HealthState.checking;
    healthMessage = null;
    _notify();
    final result = await _relay.checkHealth(trimmed);
    result.fold(
      (_) {
        healthState = HealthState.healthy;
        healthMessage = null;
      },
      (error) {
        healthState = HealthState.unhealthy;
        healthMessage = error.message;
      },
    );
    _notify();
  }

  /// Clear a stale health result when the URL starts changing.
  void clearHealth() {
    if (healthState == HealthState.unknown && healthMessage == null) return;
    healthState = HealthState.unknown;
    healthMessage = null;
    _notify();
  }

  /// Load paired devices into their independent loading or error state.
  ///
  /// Listener notifications are suppressed if this ViewModel is disposed while
  /// the gateway request is pending.
  Future<void> loadDevices() async {
    devicesLoad = ConnLoad.loading;
    devicesError = null;
    _notify();
    final result = await _relay.listDevices();
    result.fold(
      (list) {
        devices = list;
        devicesLoad = ConnLoad.ready;
      },
      (error) {
        devicesError = error.message;
        devicesLoad = ConnLoad.error;
      },
    );
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

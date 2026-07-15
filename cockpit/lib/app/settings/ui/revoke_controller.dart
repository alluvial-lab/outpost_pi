import 'package:cockpit/app/core/domain/contracts/revoke_gateway.dart';
import 'package:cockpit/app/settings/domain/entities/paired_device.dart';
import 'package:flutter/foundation.dart';

/// Describe the revocation stage that drives dialog content.
enum RevokeStage { running, done, failed }

/// Manage the one-shot device-revocation dialog state.
///
/// Uses an ephemeral `pi --mode rpc` process through [RevokeGateway] to run
/// `/outpost-pi revoke <shortId>` and report completion or failure.
class RevokeController extends ChangeNotifier {
  RevokeController(this._gateway);

  final RevokeGateway _gateway;

  RevokeStage stage = RevokeStage.running;
  String? error;
  String? deviceName;

  bool _disposed = false;

  /// Run one revocation and publish its terminal state.
  ///
  /// Resets prior error state, preserves a display name for progress copy, and
  /// suppresses listener notification if completion arrives after disposal.
  Future<void> run(PairedDevice device) async {
    deviceName = device.label.isEmpty ? device.shortId : device.label;
    stage = RevokeStage.running;
    error = null;
    _notify();

    final result = await _gateway.revoke(device.shortId);
    result.fold((_) => stage = RevokeStage.done, (e) {
      error = e.message;
      stage = RevokeStage.failed;
    });
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

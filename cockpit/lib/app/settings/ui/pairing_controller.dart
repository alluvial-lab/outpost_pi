import 'dart:async';

import 'package:cockpit/app/core/domain/contracts/pairing_gateway.dart';
import 'package:cockpit/app/core/domain/entities/pair_event.dart';
import 'package:flutter/foundation.dart';

/// Describe the pairing stage that drives dialog content.
enum PairStage { connecting, showingCode, paired, failed }

/// Manage state and resources for one pairing dialog.
///
/// Creates an ephemeral [PairingGateway] per attempt, translates [PairEvent]
/// values into dialog state, and cancels subscriptions and the active gateway
/// from [dispose].
class PairingController extends ChangeNotifier {
  PairingController(this._createGateway);

  final PairingGateway Function() _createGateway;

  PairingGateway? _gateway;
  StreamSubscription<PairEvent>? _sub;

  PairStage stage = PairStage.connecting;
  PairCodeReady? code;
  String? error;
  String? pairedName;

  bool _disposed = false;

  /// Report when the dialog should close after a device pairs.
  bool get isPaired => stage == PairStage.paired;

  /// Start a fresh ephemeral pairing session.
  ///
  /// Cancels and replaces any prior subscription and gateway before resetting
  /// state. Listener notifications from late work are suppressed after disposal.
  Future<void> start() async {
    // Close a previous retry session before opening another.
    await _sub?.cancel();
    await _gateway?.cancel();

    stage = PairStage.connecting;
    code = null;
    error = null;
    _notify();

    final gateway = _createGateway();
    _gateway = gateway;
    _sub = gateway.events.listen(_onEvent, onError: (Object e) => _fail('$e'));
    await gateway.start(ttl: const Duration(seconds: 120));
  }

  /// Retry pairing by replacing the current ephemeral session.
  Future<void> retry() => start();

  void _onEvent(PairEvent event) {
    switch (event) {
      case PairCodeReady():
        code = event;
        error = null;
        stage = PairStage.showingCode;
        _notify();
      case PairDevicePaired():
        pairedName = event.name;
        stage = PairStage.paired;
        _notify();
      case PairFailed():
        _fail(event.message);
    }
  }

  void _fail(String message) {
    // Ignore process-shutdown noise after pairing has succeeded.
    if (stage == PairStage.paired) return;
    error = message;
    stage = PairStage.failed;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _gateway?.cancel();
    super.dispose();
  }
}

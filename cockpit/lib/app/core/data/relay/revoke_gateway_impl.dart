import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/core/data/relay/ephemeral_pi_rpc.dart';
import 'package:cockpit/app/core/domain/contracts/revoke_gateway.dart';
import 'package:cockpit/app/core/domain/exceptions/relay_error.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Create a [RevokeGateway] backed by a fresh `pi --mode rpc` process.
class RevokeGatewayFactoryImpl implements RevokeGatewayFactory {
  RevokeGatewayFactoryImpl(this._config);

  final PiSpawnConfig _config;

  @override
  RevokeGateway create() => RevokeGatewayImpl(_config);
}

/// Implement [RevokeGateway] over an [EphemeralPiRpc] session.
///
/// Sends the one-shot `/outpost-pi revoke <shortId>` command and waits for a
/// confirmation notification. Unlike pairing, revoke emits no custom event;
/// it reports through `extension_ui_request`/`notify`:
/// - success → `[outpost-pi] Revoked: <name> …` (info)
/// - failure → warning (`No peer matching`, `Revoke requires the relay`, …)
class RevokeGatewayImpl implements RevokeGateway {
  RevokeGatewayImpl(this._config);

  final PiSpawnConfig _config;

  @override
  Future<Result<void, RelayError>> revoke(
    String shortId, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final rpc = EphemeralPiRpc(_config);
    final completer = Completer<Result<void, RelayError>>();

    void finish(Result<void, RelayError> result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    try {
      final command = jsonEncode(<String, dynamic>{
        'type': 'prompt',
        'message': '/outpost-pi revoke $shortId',
      });
      await rpc.start(
        prompt: command,
        onLine: (json) => _onLine(json, finish),
        onExit: (code) => finish(
          Failure(
            RelayError('The process exited before confirming (code=$code).'),
          ),
        ),
      );
    } catch (error, stackTrace) {
      await rpc.dispose();
      return Failure(
        RelayError(
          'Failed to revoke: $error',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }

    final timer = Timer(
      timeout,
      () => finish(
        const Failure(
          RelayError('Timed out revoking. Check the connection to the relay.'),
        ),
      ),
    );

    final result = await completer.future;
    timer.cancel();
    await rpc.dispose();
    return result;
  }

  void _onLine(
    Map<String, dynamic> json,
    void Function(Result<void, RelayError>) finish,
  ) {
    if (json['type'] != 'extension_ui_request' || json['method'] != 'notify') {
      return;
    }
    final message = (json['message'] as String?) ?? '';
    if (message.contains('Revoked:')) {
      finish(const Success(null));
      return;
    }
    // Treat outpost-pi warnings during revoke as failures: missing peer,
    // unavailable relay, ambiguous short id, or incomplete setup.
    if (json['notifyType'] == 'warning' && message.contains('outpost-pi')) {
      finish(Failure(RelayError(_clean(message))));
    }
  }

  String _clean(String message) =>
      message.replaceFirst('[outpost-pi] ', '').trim();
}

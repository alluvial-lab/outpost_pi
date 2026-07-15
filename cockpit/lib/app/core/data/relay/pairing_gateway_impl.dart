import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/core/data/relay/ephemeral_pi_rpc.dart';
import 'package:cockpit/app/core/domain/contracts/pairing_gateway.dart';
import 'package:cockpit/app/core/domain/entities/pair_event.dart';

/// Create a [PairingGateway] backed by a fresh ephemeral RPC session.
///
/// Each pairing attempt owns its own `pi --mode rpc` process.
class PairingGatewayFactoryImpl implements PairingGatewayFactory {
  PairingGatewayFactoryImpl(this._config);

  final PiSpawnConfig _config;

  @override
  PairingGateway create() => PairingGatewayImpl(_config);
}

/// Implement [PairingGateway] over an [EphemeralPiRpc] session.
///
/// Runs `/outpost-pi pair` and converts stdout messages with `role: "custom"`
/// (`outpost-pi:pair-code` and `outpost-pi:paired`) into [PairEvent] values. Each
/// pair code arrives twice, as `message_start` and `message_end` with identical
/// payloads, so events are deduplicated by signature.
class PairingGatewayImpl implements PairingGateway {
  PairingGatewayImpl(PiSpawnConfig config) : _rpc = EphemeralPiRpc(config);

  final EphemeralPiRpc _rpc;
  final StreamController<PairEvent> _events =
      StreamController<PairEvent>.broadcast();

  final Set<String> _seen = <String>{};
  bool _started = false;
  bool _gotCode = false;
  bool _closed = false;
  Timer? _bootTimeout;

  @override
  Stream<PairEvent> get events => _events.stream;

  @override
  Future<void> start({Duration ttl = const Duration(seconds: 120)}) async {
    if (_started) return;
    _started = true;
    try {
      final command = jsonEncode(<String, dynamic>{
        'type': 'prompt',
        'message': '/outpost-pi pair --ttl ${ttl.inSeconds}',
      });
      await _rpc.start(prompt: command, onLine: _onLine, onExit: _onExit);

      // `/outpost-pi pair` starts the relay connection itself. Allow time for
      // that connection before failing; no pair code indicates a missing
      // extension or unavailable relay.
      _bootTimeout = Timer(const Duration(seconds: 30), () {
        if (!_gotCode) {
          _emit(
            const PairFailed(
              'Could not start pairing. Check that the outpost-pi extension is '
              'installed and that a relay is configured.',
            ),
          );
        }
      });
    } catch (error) {
      _emit(PairFailed('Failed to start pairing: $error'));
      await _cleanup();
    }
  }

  @override
  Future<void> cancel() => _cleanup();

  void _onLine(Map<String, dynamic> json) {
    final type = json['type'];
    if (type != 'message_start' && type != 'message_end') return;
    final message = json['message'];
    if (message is! Map || message['role'] != 'custom') return;
    final details = message['details'];
    _handleCustom(
      message['customType'] as String?,
      details is Map ? details : const <dynamic, dynamic>{},
    );
  }

  void _handleCustom(String? customType, Map<dynamic, dynamic> details) {
    if (customType == null) return;
    final signature = '$customType|${jsonEncode(details)}';
    if (!_seen.add(signature)) return; // Deduplicate start/end messages.

    switch (customType) {
      case 'outpost-pi:pair-code':
        final uri = details['uri'];
        if (uri is! String || uri.isEmpty) return;
        _gotCode = true;
        _bootTimeout?.cancel();
        _emit(
          PairCodeReady(
            uri: uri,
            token: details['token']?.toString(),
            expiresAt: details['expiresAt']?.toString(),
            roomId: details['roomId']?.toString(),
            name: details['name']?.toString(),
          ),
        );
      case 'outpost-pi:paired':
        _emit(PairDevicePaired(name: details['name']?.toString()));
    }
  }

  void _onExit(int code) {
    if (!_gotCode && !_closed) {
      _emit(PairFailed('The pairing process exited (code=$code).'));
    }
    unawaited(_cleanup());
  }

  Future<void> _cleanup() async {
    if (_closed) return;
    _closed = true;
    _bootTimeout?.cancel();
    await _rpc.dispose();
    if (!_events.isClosed) await _events.close();
  }

  void _emit(PairEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}

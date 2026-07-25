import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

/// Implement [PairingGateway] over an [EphemeralPiRpcSession].
///
/// The gateway gives its child process a Cockpit-owned, private file path through
/// `OUTPOST_PI_PAIR_CODE_FILE`, then polls that path for the token-bearing pair
/// code. It only consumes token-free `outpost-pi:paired` custom messages from
/// the RPC stream and removes the seam file when the attempt ends.
class PairingGatewayImpl implements PairingGateway {
  PairingGatewayImpl(
    PiSpawnConfig config, {
    EphemeralPiRpcSession? rpc,
    this.bootTimeout = const Duration(seconds: 30),
    this.pollInterval = const Duration(milliseconds: 50),
  }) : _rpc = rpc ?? EphemeralPiRpc(config);

  final EphemeralPiRpcSession _rpc;
  final Duration bootTimeout;
  final Duration pollInterval;
  final StreamController<PairEvent> _events =
      StreamController<PairEvent>.broadcast();

  final Set<String> _seen = <String>{};
  bool _started = false;
  bool _gotCode = false;
  bool _closed = false;
  Timer? _bootTimeout;
  Timer? _pollTimer;
  Directory? _pairCodeDirectory;
  File? _pairCodeFile;

  @override
  Stream<PairEvent> get events => _events.stream;

  @override
  Future<void> start({Duration ttl = const Duration(seconds: 120)}) async {
    if (_started) return;
    _started = true;
    try {
      final pairCodeFile = await _createPairCodeFile();
      final command = jsonEncode(<String, dynamic>{
        'type': 'prompt',
        'message': '/outpost-pi pair --ttl ${ttl.inSeconds}',
      });
      await _rpc.start(
        prompt: command,
        onLine: _onLine,
        onExit: _onExit,
        additionalEnvironment: <String, String>{
          'OUTPOST_PI_PAIR_CODE_FILE': pairCodeFile.path,
        },
      );
      await _pollPairCodeFile();
      if (!_gotCode) {
        _pollTimer = Timer.periodic(pollInterval, (_) {
          unawaited(_pollPairCodeFile());
        });
        _bootTimeout = Timer(bootTimeout, () {
          if (!_gotCode) {
            _emit(
              const PairFailed(
                'Could not start pairing. Check that the outpost-pi extension is '
                'installed and that a relay is configured.',
              ),
            );
          }
        });
      }
    } catch (error) {
      _emit(PairFailed('Failed to start pairing: $error'));
      await _cleanup();
    }
  }

  @override
  Future<void> cancel() => _cleanup();

  Future<File> _createPairCodeFile() async {
    // Directory.createTemp uses a 0700 directory on supported platforms; the
    // child receives only the path inside this Cockpit-owned directory.
    final directory = await Directory.systemTemp.createTemp('outpost-pi-pair-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}pair-code.json',
    );
    _pairCodeDirectory = directory;
    _pairCodeFile = file;
    return file;
  }

  Future<void> _pollPairCodeFile() async {
    if (_closed || _gotCode) return;
    final file = _pairCodeFile;
    if (file == null || !await file.exists()) return;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final uri = decoded['uri'];
      final token = decoded['token'];
      final expiresAt = decoded['expiresAt'];
      final roomId = decoded['roomId'];
      final name = decoded['name'];
      if (uri is! String ||
          uri.isEmpty ||
          token is! String ||
          token.isEmpty ||
          expiresAt is! num ||
          roomId is! String ||
          roomId.isEmpty ||
          name is! String ||
          name.isEmpty) {
        return;
      }

      _gotCode = true;
      _bootTimeout?.cancel();
      _pollTimer?.cancel();
      _emit(
        PairCodeReady(
          uri: uri,
          token: token,
          expiresAt: expiresAt.toString(),
          roomId: roomId,
          name: name,
        ),
      );
    } on FileSystemException catch (_) {
      // The extension may be atomically replacing the seam file; retry on the
      // next poll rather than exposing a partial filesystem state to the UI.
    } on FormatException catch (_) {
      // A non-seam file must not become a pairing event.
    }
  }

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
    if (customType != 'outpost-pi:paired') return;
    final signature = '$customType|${jsonEncode(details)}';
    if (!_seen.add(signature)) return; // Deduplicate start/end messages.
    _emit(PairDevicePaired(name: details['name']?.toString()));
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
    _pollTimer?.cancel();
    await _rpc.dispose();
    final directory = _pairCodeDirectory;
    _pairCodeDirectory = null;
    _pairCodeFile = null;
    if (directory != null) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        // Cleanup is best-effort after process exit or cancellation.
      }
    }
    if (!_events.isClosed) await _events.close();
  }

  void _emit(PairEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}

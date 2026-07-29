import 'dart:async';
import 'dart:io' show Platform;

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/pair_request_flow.dart' as pair_flow;
import 'package:app/pairing/qr_scanner.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:cryptography/cryptography.dart';

/// Create the connected transport for one QR pairing attempt.
///
/// The caller owns the returned transport until pairing transfers it to a live
/// channel, and must close it when that handoff cannot complete. Production
/// uses `WsTransport.connect`; tests use an in-memory pipe.
typedef PairingTransportFactory =
    Future<pair_flow.PeerTransport> Function(
      QrPairPayload qr,
      SimpleKeyPair deviceEd25519,
    );

/// Drive QR pairing and expose scanning, connection, success, and error state.
///
/// Owns each transient transport until it becomes a [SecurePeerChannel]
/// adopted by [ConnectionManager], closing it after a failed pairing attempt.
class PairingViewModel extends ViewModel<PairingState> {
  final PairingStorage _storage;
  final PairingTransportFactory _transportFactory;
  // Plan/31 — connection lifecycle (disconnect/adopt) now goes straight to
  // the ConnectionManager (the removed SessionRepository was a pass-through).
  final ConnectionManager _conn;
  final Preferences _prefs;
  final OwnerIdentityBridge _ownerBridge;
  final DebugLog? _debugLog;
  _PairingAttempt? _activeAttempt;
  int _generation = 0;
  bool _disposed = false;

  PairingViewModel(
    this._storage,
    this._transportFactory,
    this._conn,
    this._prefs,
    this._ownerBridge, {
    DebugLog? debugLog,
  }) : _debugLog = debugLog,
       super(const PairingScanning());

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Called when MobileScanner detects a barcode.
  Future<void> onQrScanned(String rawUri) async {
    if (_disposed || state is PairingConnecting) return;
    final generation = ++_generation;

    final qr = QrPairPayload.tryParse(rawUri);
    if (qr == null) {
      // A camera scan of a non-Outpost-Pi barcode is silently ignored.
      // But a pasted/typed code that looks like a pairing attempt (contains
      // the outpostpi scheme or pair? query) but failed to parse deserves
      // explicit feedback — otherwise the paste sheet closes and the user
      // sees no indication their code was rejected.
      final looksIntentional = rawUri.contains('outpostpi://') ||
          rawUri.contains('pair?');
      if (looksIntentional) {
        _emitIfCurrent(
          generation,
          const PairingError(
            message: 'That pairing code could not be read. Make sure it '
                'starts with outpostpi://pair? and was copied whole.',
            canRetry: true,
          ),
        );
      }
      return;
    }

    final relayResolution = resolveRelayUrl(_prefs);
    if (relayResolution is! ConfiguredRelay) {
      _emitIfCurrent(
        generation,
        const PairingError(
          message: kRelayNotConfiguredMessage,
          canRetry: false,
        ),
      );
      return;
    }

    _emitIfCurrent(generation, PairingConnecting(sessionName: qr.sessionName));

    _PairingAttempt? attempt;
    try {
      // Close any active session before opening a new WS to the relay.
      // Same device Ed25519 key on a second WS would collide in the relay's
      // peer registry, causing the old handler to unregister our new entry.
      await _conn.disconnect();
      if (!_isCurrent(generation)) return;

      // Plan 23 — challenge-response now uses the Owner-key (synced
      // via iCloud Keychain / Block Store). The bridge is hydrated by
      // the router's _BootState well before pairing is reachable, so
      // requireKeyPair() never throws here.
      final ownerKey = await _ownerBridge.requireKeyPair();
      if (!_isCurrent(generation)) return;

      final transport = await _transportFactory(qr, ownerKey);
      if (!_isCurrent(generation)) {
        await transport.close();
        return;
      }
      attempt = _PairingAttempt(transport);
      _activeAttempt = attempt;

      final result = await pair_flow
          .performPairing(
            qr: qr,
            transport: transport,
            storage: _storage,
            ownerKey: ownerKey,
            deviceName: _deviceName(),
            persistPeer: false,
            currentRelayUrl: relayResolution.url,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw const pair_flow.PairingError(
              code: 'pair_timeout',
              message:
                  'Timed out — make sure /outpost-pi is running on your Mac',
            ),
          );
      if (!_isCurrent(generation)) {
        await _closeAttempt(attempt);
        return;
      }
      final persisted = await _storage.savePairedPeerIfCurrent(
        result.peer,
        stillCurrent: () => _isCurrent(generation),
      );
      if (!persisted) {
        await _closeAttempt(attempt);
        return;
      }

      final channel = SecurePeerChannel(
        transport: transport,
        storage: _storage,
        peer: result.peer,
        debugLog: _debugLog,
      );
      attempt.attachChannel(channel);
      if (!_isCurrent(generation)) {
        await _closeAttempt(attempt);
        return;
      }
      _conn.adopt(channel, result.peer);
      _releaseAttempt(attempt);

      _emitIfCurrent(
        generation,
        PairingPaired(peer: result.peer, hostnameHint: result.hostnameHint),
      );
    } on RelayNotConfiguredException {
      await _closeAttempt(attempt);
      _emitIfCurrent(
        generation,
        const PairingError(
          message: kRelayNotConfiguredMessage,
          canRetry: false,
        ),
      );
    } on pair_flow.PairingError catch (e) {
      await _closeAttempt(attempt);
      _emitIfCurrent(
        generation,
        PairingError(message: _friendlyError(e), canRetry: true),
      );
    } catch (e) {
      await _closeAttempt(attempt);
      _emitIfCurrent(
        generation,
        PairingError(message: e.toString(), canRetry: true),
      );
    }
  }

  /// Retry after an error.
  void retry() {
    if (_disposed) return;
    _generation++;
    final attempt = _activeAttempt;
    _activeAttempt = null;
    if (attempt != null) unawaited(attempt.close());
    emit(const PairingScanning());
  }

  /// Persist a nickname on the just-paired peer. Called by the
  /// post-pair nickname modal (plan/27 Wave A) — `null` or empty
  /// leaves the existing record unchanged, anything else is written
  /// back through [PairingStorage.savePeer], whose mutation hook
  /// republishes `mesh_versions` so other devices learn the label.
  ///
  /// The trimmed nickname is also reflected on the in-state peer so
  /// the post-frame navigation to /home shows the chosen label
  /// immediately (no flicker waiting for `loadPeer`).
  Future<void> applyNickname(String? nickname) async {
    if (_disposed) return;
    final generation = _generation;
    final s = state;
    if (s is! PairingPaired) return;
    final trimmed = nickname?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    final updated = s.peer.copyWith(nickname: trimmed);
    await _storage.savePeer(updated);
    _emitIfCurrent(
      generation,
      PairingPaired(peer: updated, hostnameHint: s.hostnameHint),
    );
  }

  // ---------------------------------------------------------------------------

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _emitIfCurrent(int generation, PairingState next) {
    if (_isCurrent(generation)) emit(next);
  }

  Future<void> _closeAttempt(_PairingAttempt? attempt) async {
    if (attempt == null) return;
    if (identical(_activeAttempt, attempt)) _activeAttempt = null;
    await attempt.close();
  }

  void _releaseAttempt(_PairingAttempt attempt) {
    if (identical(_activeAttempt, attempt)) _activeAttempt = null;
    attempt.release();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    final attempt = _activeAttempt;
    _activeAttempt = null;
    if (attempt != null) unawaited(attempt.close());
    super.dispose();
  }

  static String _friendlyError(pair_flow.PairingError e) => switch (e.code) {
    'token_expired' => 'QR expired — generate a new one on your Mac',
    'token_consumed' => 'QR already used — generate a new one',
    'token_unknown' => 'QR not recognized by Mac — re-run /outpost-pi pair',
    'pair_timeout' =>
      'Timed out — make sure /outpost-pi is running on your Mac',
    _ => e.message.isEmpty ? e.code : e.message,
  };

  static String _deviceName() {
    try {
      if (Platform.isIOS) return 'iPhone';
      if (Platform.isAndroid) return 'Android device';
      return 'Mobile';
    } catch (_) {
      return 'Mobile';
    }
  }
}

/// Own the transport or channel created by one pairing generation.
///
/// A stale completion closes this captured object, never the ViewModel's
/// mutable active-attempt reference, which may belong to a later QR scan.
final class _PairingAttempt {
  _PairingAttempt(this._transport);

  final pair_flow.PeerTransport _transport;
  SecurePeerChannel? _channel;
  bool _closed = false;
  bool _released = false;

  void attachChannel(SecurePeerChannel channel) {
    if (_closed) {
      unawaited(channel.close());
      return;
    }
    _channel = channel;
  }

  void release() {
    _released = true;
    _channel = null;
  }

  Future<void> close() async {
    if (_closed || _released) return;
    _closed = true;
    final channel = _channel;
    if (channel != null) {
      await channel.close();
    } else {
      await _transport.close();
    }
  }
}

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
  pair_flow.PeerTransport? _transport;
  SecurePeerChannel? _liveChannel;
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
    if (qr == null) return; // not an outpostpi:// QR — ignore silently

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
      _transport = transport;

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
        await _closeTransient();
        return;
      }
      await _storage.savePairedPeer(result.peer);
      if (!_isCurrent(generation)) {
        await _closeTransient();
        return;
      }

      final channel = SecurePeerChannel(
        transport: transport,
        storage: _storage,
        peer: result.peer,
        debugLog: _debugLog,
      );
      if (!_isCurrent(generation)) {
        await channel.close();
        return;
      }
      _liveChannel = channel;
      _transport = null; // channel now owns the transport

      if (!_isCurrent(generation)) {
        await _closeTransient();
        return;
      }
      _conn.adopt(channel, result.peer);
      _liveChannel = null;

      _emitIfCurrent(
        generation,
        PairingPaired(peer: result.peer, hostnameHint: result.hostnameHint),
      );
    } on RelayNotConfiguredException {
      await _closeTransient();
      _emitIfCurrent(
        generation,
        const PairingError(
          message: kRelayNotConfiguredMessage,
          canRetry: false,
        ),
      );
    } on pair_flow.PairingError catch (e) {
      await _closeTransient();
      _emitIfCurrent(
        generation,
        PairingError(message: _friendlyError(e), canRetry: true),
      );
    } catch (e) {
      await _closeTransient();
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
    unawaited(_closeTransient());
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

  Future<void> _closeTransient() async {
    final liveChannel = _liveChannel;
    final transport = _transport;
    _liveChannel = null;
    _transport = null;
    await liveChannel?.close();
    await transport?.close();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    unawaited(_closeTransient());
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

import 'dart:async';

import 'package:app/data/identity/device_id.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_cancellation.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/data/transport/relay_config.dart';
import 'package:app/data/transport/peer_channel.dart';
import 'package:app/data/transport/ws_transport.dart';
import 'package:app/domain/contracts/debug_log.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/pair_request_flow.dart';
import 'package:app/pairing/storage.dart';
import 'package:cryptography/cryptography.dart';

/// Connect one candidate relay transport for an established peer.
///
/// The cancellation capability belongs to this individual candidate attempt;
/// implementations must close their resources when it is cancelled.
typedef ProductionTransportConnector =
    Future<PeerTransport> Function({
      required String relayUrl,
      required String peerPubkey,
      required SimpleKeyPair ed25519Key,
      required String deviceId,
      required String activeRoom,
      required DebugLog? debugLog,
      required ConnectionCancellation cancellation,
    });

/// Compose the authenticated, owner-channel-protected reconnect path.
///
/// Resolves the configured relay at call time, then tries its retained paired
/// endpoint in order. Each candidate gets a child cancellation token so a
/// failed or superseded attempt settles before the next candidate starts.
class ProductionConnectionFactory {
  final RelayResolution Function() _relayResolution;
  final PairingStorage _storage;
  final OwnerIdentityBridge _ownerIdentity;
  final DeviceId _deviceId;
  final DebugLog? _debugLog;
  final ProductionTransportConnector _connectTransport;

  /// Create the production reconnect factory.
  ///
  /// [connectTransport] is injectable so the candidate ordering and
  /// cancellation boundary can be tested without opening real sockets. The
  /// default is the app's authenticated [WsTransport] connector.
  ProductionConnectionFactory({
    required RelayResolution Function() relayResolution,
    required PairingStorage storage,
    required OwnerIdentityBridge ownerIdentity,
    required DeviceId deviceId,
    required DebugLog? debugLog,
    ProductionTransportConnector? connectTransport,
  }) : _relayResolution = relayResolution,
       _storage = storage,
       _ownerIdentity = ownerIdentity,
       _deviceId = deviceId,
       _debugLog = debugLog,
       _connectTransport = connectTransport ?? _connectWsTransport;

  /// Establish an owner-channel-protected connection for [peer].
  ///
  /// Throws [RelayNotConfiguredException] when no configured relay exists and
  /// rethrows the final candidate failure when every endpoint is unavailable.
  /// Parent cancellation aborts the current candidate and never advances to a
  /// later endpoint.
  Future<IChannel> call(PeerRecord peer, CancelToken cancel) async {
    final resolution = _relayResolution();
    if (resolution is! ConfiguredRelay) {
      throw const RelayNotConfiguredException();
    }
    final relayUrls = orderedRelayUrls(resolution.url, [peer.relayUrl]);
    // ConnectionManager retries with the peer snapshot that originally opened
    // the channel. Reload here so persisted sequence advances are never reset
    // by a stale in-memory PeerRecord after a transient disconnect.
    final channelPeer = await _storage.loadPeer(peer.remoteEpk);
    if (channelPeer?.channel == null) {
      throw const PeerChannelError(
        'paired peer predates owner-channel protection; re-pair required',
      );
    }
    if (cancel.isCancelled) throw const _CancelledError();

    final ownerKey = await _ownerIdentity.requireKeyPair();
    if (cancel.isCancelled) throw const _CancelledError();

    // Defensive timeout: without this the WebSocket connect + Ed25519
    // challenge round-trip can hang indefinitely if the relay is unreachable.
    // Each candidate owns a child cancellation token so a timed-out path is
    // closed before the next endpoint is attempted.
    const wsConnectTimeout = Duration(seconds: 10);
    Object? lastError;
    StackTrace? lastStack;
    for (final relayUrl in relayUrls) {
      if (cancel.isCancelled) throw const _CancelledError();
      final attemptCancel = CancelToken();
      Future<void> parentCancellation() => attemptCancel.cancelAndWait();
      cancel.addCancellationListener(parentCancellation);
      try {
        // Construct the transport with the real destination room from the
        // start so post-auth frames are demuxed against the correct room from
        // frame 1.
        final transport =
            await _connectTransport(
              relayUrl: relayUrl,
              peerPubkey: channelPeer!.remoteEpk,
              ed25519Key: ownerKey,
              deviceId: await _deviceId.get(),
              activeRoom: channelPeer.roomId ?? 'main',
              debugLog: _debugLog,
              cancellation: attemptCancel,
            ).timeout(
              wsConnectTimeout,
              onTimeout: () => throw TimeoutException(
                'WS connect to $relayUrl timed out after '
                '${wsConnectTimeout.inSeconds}s',
              ),
            );

        if (cancel.isCancelled) {
          await transport.close();
          throw const _CancelledError();
        }

        return SecurePeerChannel(
          transport: transport,
          storage: _storage,
          peer: channelPeer,
          debugLog: _debugLog,
        );
      } catch (error, stack) {
        if (cancel.isCancelled) throw const _CancelledError();
        lastError = error;
        lastStack = stack;
        await attemptCancel.cancelAndWait();
      } finally {
        cancel.removeCancellationListener(parentCancellation);
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack!);
  }
}

Future<PeerTransport> _connectWsTransport({
  required String relayUrl,
  required String peerPubkey,
  required SimpleKeyPair ed25519Key,
  required String deviceId,
  required String activeRoom,
  required DebugLog? debugLog,
  required ConnectionCancellation cancellation,
}) => WsTransport.connect(
  relayUrl: relayUrl,
  peerPubkey: peerPubkey,
  ed25519Key: ed25519Key,
  deviceId: deviceId,
  activeRoom: activeRoom,
  debugLog: debugLog,
  cancellation: cancellation,
);

class _CancelledError implements Exception {
  const _CancelledError();
}

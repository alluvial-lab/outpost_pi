import 'dart:convert';

import 'package:app/protocol/protocol.dart' show PiHarness;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _kPeersService = 'dev.outpostpi.peers';
const _kChannelsService = 'dev.outpostpi.owner-channels';
const _kRoomsService = 'dev.outpostpi.rooms';

/// Plan-17 follow-up — persisted snapshot of every room we have ever
/// learned about for a peer (relay-announced via `room_announced` /
/// `rooms` push). Allows Home to keep showing the same tiles after a
/// cold start while the relay is still warming up + lets the user
/// open a chat offline and read history.
class PersistedRoom {
  final String roomId;
  final String? name;
  final String? cwd;
  final int startedAt;

  /// Local-only override for [name]. When non-null, takes precedence
  /// in UI (long-press rename).
  final String? localName;

  /// Plan 18 — last-known model the Pi-extension is running with.
  /// Persisted so the subtitle survives cold starts.
  final String? model;

  const PersistedRoom({
    required this.roomId,
    required this.startedAt,
    this.name,
    this.cwd,
    this.localName,
    this.model,
  });

  Map<String, dynamic> toJson() => {
    'room_id': roomId,
    'name': name,
    'cwd': cwd,
    'started_at': startedAt,
    'local_name': localName,
    'model': model,
  };

  factory PersistedRoom.fromJson(Map<String, dynamic> j) => PersistedRoom(
    roomId: j['room_id'] as String,
    name: j['name'] as String?,
    cwd: j['cwd'] as String?,
    startedAt: (j['started_at'] as num).toInt(),
    localName: j['local_name'] as String?,
    model: j['model'] as String?,
  );

  PersistedRoom copyWith({
    String? name,
    String? cwd,
    int? startedAt,
    Object? localName = _unset,
    Object? model = _unset,
  }) => PersistedRoom(
    roomId: roomId,
    name: name ?? this.name,
    cwd: cwd ?? this.cwd,
    startedAt: startedAt ?? this.startedAt,
    localName: identical(localName, _unset)
        ? this.localName
        : localName as String?,
    model: identical(model, _unset) ? this.model : model as String?,
  );
}

// ---------------------------------------------------------------------------
// PeerRecord — persisted per pairing
// ---------------------------------------------------------------------------

/// Persist the two directional owner-channel keys and sequence high-water marks.
///
/// Keys are standard-base64 32-byte values. This object is stored under a
/// dedicated [FlutterSecureStorage] entry rather than inside mesh-visible peer
/// metadata. Sequence values are signed-positive Dart integers; exhaustion at
/// `2^63 - 1` fails closed, far before practical nonce collision risk.
final class OwnerChannelState {
  OwnerChannelState({
    required this.sendKey,
    required this.receiveKey,
    this.sendSequence = 0,
    this.receiveSequence = 0,
  }) {
    _validateKey(sendKey, 'sendKey');
    _validateKey(receiveKey, 'receiveKey');
    if (sendSequence < 0 ||
        sendSequence > 0x7fffffffffffffff ||
        receiveSequence < 0 ||
        receiveSequence > 0x7fffffffffffffff) {
      throw ArgumentError(
        'owner-channel sequences must fit the non-negative signed-64 range',
      );
    }
  }

  final String sendKey;
  final String receiveKey;
  final int sendSequence;
  final int receiveSequence;

  Map<String, dynamic> toJson() => {
    'send_key': sendKey,
    'receive_key': receiveKey,
    'send_seq': sendSequence,
    'receive_seq': receiveSequence,
  };

  factory OwnerChannelState.fromJson(Map<String, dynamic> json) {
    final sendSequence = json['send_seq'];
    final receiveSequence = json['receive_seq'];
    if (sendSequence is! int || receiveSequence is! int) {
      throw const FormatException('owner-channel sequences must be integers');
    }
    return OwnerChannelState(
      sendKey: json['send_key'] as String,
      receiveKey: json['receive_key'] as String,
      sendSequence: sendSequence,
      receiveSequence: receiveSequence,
    );
  }

  OwnerChannelState copyWith({int? sendSequence, int? receiveSequence}) =>
      OwnerChannelState(
        sendKey: sendKey,
        receiveKey: receiveKey,
        sendSequence: sendSequence ?? this.sendSequence,
        receiveSequence: receiveSequence ?? this.receiveSequence,
      );

  static void _validateKey(String encoded, String name) {
    try {
      if (base64.decode(encoded).length != 32) {
        throw FormatException('$name must encode 32 bytes');
      }
    } on FormatException {
      throw FormatException('$name must be standard base64 for 32 bytes');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is OwnerChannelState &&
      other.sendKey == sendKey &&
      other.receiveKey == receiveKey &&
      other.sendSequence == sendSequence &&
      other.receiveSequence == receiveSequence;

  @override
  int get hashCode =>
      Object.hash(sendKey, receiveKey, sendSequence, receiveSequence);
}

// Sentinel for nullable copyWith parameters that need to distinguish
// "keep current" (omit) from "set to null" (pass `null` explicitly).
const Object _unset = Object();

/// Persist one paired Pi's identity and locally learned connection metadata.
///
/// The remote EPK is the durable peer identity; room labels and relay details
/// support reconnect and display but are not independent identities.
class PeerRecord {
  // base64 Ed25519 pubkey of the Pi — the only peer identifier post-rollback.
  final String remoteEpk;
  final String sessionName;
  final String relayUrl;
  final String pairedAt; // ISO-8601
  // Local-only display label (Pi does not know about this). Renders in
  // place of [sessionName] when set; null = use sessionName everywhere.
  final String? nickname;

  /// Plan 17 fix — Pi-side room id (cwd-session) this pairing is bound
  /// to. Set from `PairOk.roomId` on pair, or discovered lazily via
  /// `subscribe_rooms` for legacy peers persisted before this fix.
  /// `null` = not yet discovered; outbound sends fall back to 'main'
  /// while ConnectionManager runs the discovery once.
  final String? roomId;

  /// Plan/27 Wave A — agent harness reported by the PC at pair time.
  /// Surfaced as the "via Pi coding agent" subtitle on the PiCard.
  /// `null` for PeerRecords saved before the field existed; consumers
  /// fall back to [PiHarness.piCodingAgentUnknown] so the UI never
  /// renders an empty subtitle.
  final PiHarness? harness;

  /// E2E owner-channel material. Null only for pre-cutover legacy records.
  final OwnerChannelState? channel;

  const PeerRecord({
    required this.remoteEpk,
    required this.sessionName,
    required this.relayUrl,
    required this.pairedAt,
    this.nickname,
    this.roomId,
    this.harness,
    this.channel,
  });

  Map<String, dynamic> toJson() => {
    'remote_epk': remoteEpk,
    'session_name': sessionName,
    'relay_url': relayUrl,
    'paired_at': pairedAt,
    'nickname': nickname,
    'room_id': roomId,
    if (harness != null) 'harness': harness!.toJson(),
    // Channel secrets intentionally live in a separate secure-storage entry.
  };

  factory PeerRecord.fromJson(Map<String, dynamic> j) {
    final harnessJson = j['harness'];
    return PeerRecord(
      remoteEpk: j['remote_epk'] as String,
      sessionName: j['session_name'] as String,
      relayUrl: j['relay_url'] as String,
      pairedAt: j['paired_at'] as String,
      // Legacy records (saved before plan 10.3) have no 'nickname' field.
      nickname: j['nickname'] as String?,
      // Legacy records (saved before plan 17 fix) have no 'room_id'.
      // Stays null until ConnectionManager discovers it via subscribe_rooms.
      roomId: j['room_id'] as String?,
      // Plan/27 Wave A — harness was added later. Records saved before
      // it lack the field; null falls back to the default at consumer
      // side.
      harness: harnessJson is Map<String, dynamic>
          ? PiHarness.fromJson(harnessJson)
          : null,
    );
  }

  PeerRecord copyWith({
    String? sessionName,
    // Sentinel-typed so the caller can pass `nickname: null` to clear.
    Object? nickname = _unset,
    Object? roomId = _unset,
    Object? harness = _unset,
    Object? channel = _unset,
  }) => PeerRecord(
    remoteEpk: remoteEpk,
    sessionName: sessionName ?? this.sessionName,
    relayUrl: relayUrl,
    pairedAt: pairedAt,
    nickname: identical(nickname, _unset) ? this.nickname : nickname as String?,
    roomId: identical(roomId, _unset) ? this.roomId : roomId as String?,
    harness: identical(harness, _unset) ? this.harness : harness as PiHarness?,
    channel: identical(channel, _unset)
        ? this.channel
        : channel as OwnerChannelState?,
  );

  @override
  bool operator ==(Object other) =>
      other is PeerRecord &&
      other.remoteEpk == remoteEpk &&
      other.sessionName == sessionName &&
      other.relayUrl == relayUrl &&
      other.pairedAt == pairedAt &&
      other.nickname == nickname &&
      other.roomId == roomId &&
      other.harness == harness &&
      other.channel == channel;

  @override
  int get hashCode => Object.hash(
    remoteEpk,
    sessionName,
    relayUrl,
    pairedAt,
    nickname,
    roomId,
    harness,
    channel,
  );
}

// ---------------------------------------------------------------------------
// PairingStorage
// ---------------------------------------------------------------------------

/// The local peer-set mutation that should be published to the Owner mesh.
enum PeerMutationKind { upsert, delete }

/// Synchronous notification after a local peer mutation has committed.
typedef PeerMutationHook = void Function(PeerMutationKind kind);

/// Pairing storage with change notification.
///
/// Mutations to the peer set (`savePeer`, `deletePeer`) and to the
/// per-peer rooms cache (`saveRooms`, `deleteRooms`) call
/// `notifyListeners()` so any UI watching the storage (HomeViewModel,
/// SettingsViewModel) can refresh without manual plumbing between
/// screens. Read methods do not notify.
///
/// Peer and owner-channel mutations share one queue. This makes channel-key
/// validation and its following write atomic relative to re-pair, deletion,
/// and identity reset, so a stale channel cannot overwrite replacement keys.
class PairingStorage extends ChangeNotifier {
  final FlutterSecureStorage _store;
  Future<void> _peerMutationTail = Future<void>.value();

  /// Plan 24 — optional synchronous hook that runs after every local peer
  /// mutation. The hook receives enough intent for its owner to distinguish a
  /// legitimate last-peer deletion from an accidental empty snapshot.
  ///
  /// Room mutations are intentionally NOT hooked — rooms are a per-device
  /// cache, not synced membership. The mesh apply path uses the silent peer
  /// methods below so relay hydration cannot re-enter publication.
  PeerMutationHook? _onPeersMutated;

  PairingStorage([FlutterSecureStorage? store])
    : _store = store ?? const FlutterSecureStorage();

  /// Plug the mesh-publish callback. The hook fires after the local write and
  /// [notifyListeners], so UI sees the change before publication starts.
  /// Pass `null` to detach.
  void attachPeerMutationHook(PeerMutationHook? hook) {
    _onPeersMutated = hook;
  }

  // ---- Peer records --------------------------------------------------------

  String _peerKey(String remoteEpk) => '$_kPeersService:$remoteEpk';
  String _channelKey(String remoteEpk) => '$_kChannelsService:$remoteEpk';

  /// Persist a paired peer, notify listeners, then trigger mesh publication.
  Future<void> savePeer(PeerRecord record) => _serializePeerMutation(() async {
    await _writePeer(record);
    _onPeersMutated?.call(PeerMutationKind.upsert);
  });

  /// Same as [savePeer] but skips the mutation hook. Used by the
  /// MeshSyncService when applying a verified mesh blob to the local
  /// cache — without this we'd round-trip back to the relay
  /// (pull→apply→savePeer→hook→publish) and a race could publish an
  /// empty members list (see plan/24-fix-app-publish-race).
  Future<void> savePeerSilent(PeerRecord record) =>
      _serializePeerMutation(() => _writePeer(record));

  /// Load one peer record by its durable remote EPK, if it is still stored.
  Future<PeerRecord?> loadPeer(String remoteEpk) async {
    final raw = await _store.read(key: _peerKey(remoteEpk));
    if (raw == null) return null;
    final channelRaw = await _store.read(key: _channelKey(remoteEpk));
    return _decodePeer(raw, channelRaw);
  }

  /// Delete one peer, notify listeners, then trigger mesh publication.
  Future<void> deletePeer(String remoteEpk) => _serializePeerMutation(() async {
    await _erasePeer(remoteEpk);
    _onPeersMutated?.call(PeerMutationKind.delete);
  });

  /// Same as [deletePeer] but skips the mutation hook — see
  /// [savePeerSilent] for the rationale.
  Future<void> deletePeerSilent(String remoteEpk) =>
      _serializePeerMutation(() => _erasePeer(remoteEpk));

  Future<void> _writePeer(PeerRecord record) async {
    final peerKey = _peerKey(record.remoteEpk);
    final channelKey = _channelKey(record.remoteEpk);
    try {
      final channel = record.channel;
      if (channel != null) {
        final currentRaw = await _store.read(key: channelKey);
        final current = currentRaw == null
            ? null
            : OwnerChannelState.fromJson(
                jsonDecode(currentRaw) as Map<String, dynamic>,
              );
        final safe =
            current != null &&
                current.sendKey == channel.sendKey &&
                current.receiveKey == channel.receiveKey
            ? channel.copyWith(
                sendSequence: current.sendSequence > channel.sendSequence
                    ? current.sendSequence
                    : channel.sendSequence,
                receiveSequence:
                    current.receiveSequence > channel.receiveSequence
                    ? current.receiveSequence
                    : channel.receiveSequence,
              )
            : channel;
        await _store.write(key: channelKey, value: jsonEncode(safe.toJson()));
      }
      await _store.write(key: peerKey, value: jsonEncode(record.toJson()));
    } on Object {
      // A peer without its matching channel state must never look paired.
      await _store.delete(key: peerKey);
      await _store.delete(key: channelKey);
      rethrow;
    }
    notifyListeners();
  }

  /// Persist channel counters without publishing a mesh mutation or UI churn.
  Future<void> saveChannelState(
    String remoteEpk,
    OwnerChannelState channel,
  ) => _serializePeerMutation(() async {
    if (await _store.read(key: _peerKey(remoteEpk)) == null) {
      throw StateError('cannot persist channel state for an unknown peer');
    }
    final channelKey = _channelKey(remoteEpk);
    final currentRaw = await _store.read(key: channelKey);
    if (currentRaw == null) {
      throw StateError('cannot update missing owner-channel material');
    }
    final current = OwnerChannelState.fromJson(
      jsonDecode(currentRaw) as Map<String, dynamic>,
    );
    if (current.sendKey != channel.sendKey ||
        current.receiveKey != channel.receiveKey) {
      throw StateError('owner-channel key changed during active connection');
    }
    final monotonic = channel.copyWith(
      sendSequence: current.sendSequence > channel.sendSequence
          ? current.sendSequence
          : channel.sendSequence,
      receiveSequence: current.receiveSequence > channel.receiveSequence
          ? current.receiveSequence
          : channel.receiveSequence,
    );
    await _store.write(key: channelKey, value: jsonEncode(monotonic.toJson()));
  });

  Future<T> _serializePeerMutation<T>(Future<T> Function() mutation) {
    final operation = _peerMutationTail.then((_) => mutation());
    _peerMutationTail = operation.then<void>((_) {}).catchError((Object _) {});
    return operation;
  }

  Future<void> _erasePeer(String remoteEpk) async {
    await _store.delete(key: _peerKey(remoteEpk));
    await _store.delete(key: _channelKey(remoteEpk));
    notifyListeners();
  }

  /// List every stored peer record for bootstrap and mesh reconciliation.
  Future<List<PeerRecord>> listPeers() async {
    final all = await _store.readAll();
    final prefix = '$_kPeersService:';
    return all.entries.where((entry) => entry.key.startsWith(prefix)).map((
      entry,
    ) {
      final remoteEpk = entry.key.substring(prefix.length);
      return _decodePeer(entry.value, all[_channelKey(remoteEpk)]);
    }).toList();
  }

  PeerRecord _decodePeer(String raw, String? channelRaw) {
    final peer = PeerRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    if (channelRaw == null) return peer;
    return peer.copyWith(
      channel: OwnerChannelState.fromJson(
        jsonDecode(channelRaw) as Map<String, dynamic>,
      ),
    );
  }

  /// Wipe every peer + every persisted room map. Used by the
  /// Owner-key bridge when iCloud / Backup sync brings a different
  /// Owner-pk — the previous device's peer list is meaningless for
  /// the newly-synced identity, so we start clean rather than risk
  /// connecting against stale `remote_epk`s.
  Future<void> wipeAll() => _serializePeerMutation(() async {
    final all = await _store.readAll();
    final prefixes = [
      '$_kPeersService:',
      '$_kChannelsService:',
      '$_kRoomsService:',
    ];
    for (final key in all.keys) {
      if (prefixes.any(key.startsWith)) {
        await _store.delete(key: key);
      }
    }
    notifyListeners();
  });

  // ---- Rooms (plan 17 follow-up) -----------------------------------------

  String _roomsKey(String remoteEpk) => '$_kRoomsService:$remoteEpk';

  /// Persist the full set of known rooms for a peer. Replaces any
  /// previously stored set. Called on every room-state change in
  /// ConnectionManager so a cold start can reflect the same view.
  Future<void> saveRooms(String remoteEpk, List<PersistedRoom> rooms) async {
    await _store.write(
      key: _roomsKey(remoteEpk),
      value: jsonEncode(rooms.map((r) => r.toJson()).toList()),
    );
    notifyListeners();
  }

  /// Load cached rooms for a peer; an absent cache yields an empty list.
  Future<List<PersistedRoom>> loadRooms(String remoteEpk) async {
    final raw = await _store.read(key: _roomsKey(remoteEpk));
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => PersistedRoom.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Delete a peer's local room cache and notify reactive readers.
  Future<void> deleteRooms(String remoteEpk) async {
    await _store.delete(key: _roomsKey(remoteEpk));
    notifyListeners();
  }
}

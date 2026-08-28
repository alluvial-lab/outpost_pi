// ignore_for_file: lines_longer_than_80_chars

import 'generated/protocol.g.dart' show ThinkingLevel;
import 'generated/relay_frames.g.dart';

// ---------------------------------------------------------------------------
// Control frames (plan 12 — presence)
//
// These travel raw over the WS (no outer envelope) and are routed by the
// relay itself, not the Pi. They never enter the inner-message switch.
// ---------------------------------------------------------------------------

/// Inbound control frame (relay → app).
sealed class ControlInbound {
  const ControlInbound();

  /// Parses a top-level relay map through the generated directional DTO union.
  ///
  /// Returns null for unknown or pre-auth frame types; malformed known frames
  /// retain their typed cast failure so boundary callers can reject them.
  static ControlInbound? tryFromJson(Map<String, dynamic> json) {
    try {
      return fromWire(RelayServerControlFrameDto.fromJson(json), raw: json);
    } on FormatException {
      return null;
    }
  }

  /// Adapt a generated relay-server DTO into the app's control-domain model.
  static ControlInbound? fromWire(
    RelayServerControlFrameDto frame, {
    Map<String, dynamic>? raw,
  }) {
    bool? backgroundFrom(Map<String, dynamic>? value) {
      if (value == null) return null;
      final direct = value['background'];
      if (direct is bool) return direct;
      final nested = value['meta'];
      if (nested is Map) {
        final nestedBackground = nested['background'];
        if (nestedBackground is bool) return nestedBackground;
      }
      return null;
    }

    bool backgroundForRoom(String roomId) {
      final rooms = raw?['rooms'];
      if (rooms is List) {
        for (final entry in rooms) {
          if (entry is Map && entry['room_id'] == roomId) {
            return backgroundFrom(entry.cast<String, dynamic>()) ?? false;
          }
        }
      }
      return false;
    }

    return switch (frame) {
      RelayChallengeFrameDto() => null,
      RelayPeerOnlineFrameDto(:final peer) => PeerOnline(peer: peer),
      RelayPeerOfflineFrameDto(:final peer, :final sinceTs) => PeerOffline(
        peer: peer,
        sinceTs: sinceTs,
      ),
      RelayPresenceFrameDto(:final states) => PresenceSnapshot(
        states: states
            .map(
              (state) => PeerPresence(
                peer: state.peer,
                online: state.online,
                sinceTs: state.sinceTs,
              ),
            )
            .toList(),
      ),
      RelayRoomAnnouncedFrameDto(:final peer, :final room) => RoomAnnounced(
        peer: peer,
        roomId: room.roomId,
        sessionId: room.sessionId,
        name: room.name,
        cwd: room.cwd,
        startedAt: room.startedAt,
        model: room.model,
        thinking: room.thinking == null
            ? null
            : ThinkingLevel.fromWire(room.thinking!),
        working: room.working,
        background: backgroundFrom(raw),
      ),
      RelayRoomEndedFrameDto(:final peer, :final roomId, :final sinceTs) =>
        RoomEnded(peer: peer, roomId: roomId, sinceTs: sinceTs),
      RelayRoomsFrameDto(:final peer, :final rooms) => RoomsSnapshot(
        peer: peer,
        rooms: rooms
            .map(
              (room) => RoomInfo(
                roomId: room.roomId,
                sessionId: room.sessionId,
                name: room.name,
                cwd: room.cwd,
                startedAt: room.startedAt,
                model: room.model,
                thinking: room.thinking == null
                    ? null
                    : ThinkingLevel.fromWire(room.thinking!),
                working: room.working ?? false,
                background: backgroundForRoom(room.roomId),
              ),
            )
            .toList(),
      ),
      RelayRoomMetaUpdatedFrameDto(:final peer, :final roomId, :final meta) =>
        RoomMetaUpdated(
          peer: peer,
          roomId: roomId,
          sessionId: meta.sessionId,
          model: meta.model,
          thinking: meta.thinking == null
              ? null
              : ThinkingLevel.fromWire(meta.thinking!),
          working: meta.working,
          background: backgroundFrom(
            raw?['meta'] is Map
                ? (raw!['meta'] as Map).cast<String, dynamic>()
                : null,
          ),
          hasModel: meta.hasModel,
          hasThinking: meta.hasThinking,
          hasSessionId: meta.hasSessionId,
        ),
    };
  }
}

class PeerOnline extends ControlInbound {
  final String peer;
  const PeerOnline({required this.peer});
}

class PeerOffline extends ControlInbound {
  final String peer;
  final int sinceTs;
  const PeerOffline({required this.peer, required this.sinceTs});
}

class PresenceSnapshot extends ControlInbound {
  final List<PeerPresence> states;
  const PresenceSnapshot({required this.states});
}

class PeerPresence {
  final String peer;
  final bool online;
  final int? sinceTs;
  const PeerPresence({
    required this.peer,
    required this.online,
    required this.sinceTs,
  });

  factory PeerPresence.fromJson(Map<String, dynamic> j) => PeerPresence(
    peer: j['peer'] as String,
    online: j['online'] as bool,
    sinceTs: (j['since_ts'] as num?)?.toInt(),
  );
}

// --- Outbound control frames (helpers; the wire shape is just a Map) ---

Map<String, dynamic> subscribePresenceFrame(List<String> peers) => {
  'type': 'subscribe_presence',
  'peers': peers,
};

Map<String, dynamic> unsubscribePresenceFrame(List<String> peers) => {
  'type': 'unsubscribe_presence',
  'peers': peers,
};

Map<String, dynamic> presenceCheckFrame(List<String> peers) => {
  'type': 'presence_check',
  'peers': peers,
};

Map<String, dynamic> subscribeRoomsFrame(List<String> peers) => {
  'type': 'subscribe_rooms',
  'peers': peers,
};

Map<String, dynamic> unsubscribeRoomsFrame(List<String> peers) => {
  'type': 'unsubscribe_rooms',
  'peers': peers,
};

Map<String, dynamic> roomsCheckFrame(List<String> peers) => {
  'type': 'rooms_check',
  'peers': peers,
};

// ---------------------------------------------------------------------------
// Rooms (plan 17 — multi-cwd per Mac)
//
// Each Pi-extension instance opens one room per active session (cwd).
// The relay tracks room metadata per peer and pushes:
//   - room_announced: a new room came online for a peer
//   - room_ended: a room closed (Pi exited or stopped that cwd)
//   - rooms (snapshot): full list for a peer (sent after subscribe_rooms
//     or rooms_check).
// The app subscribes via `subscribe_rooms(peers)` and renders them as
// tiles grouped by Mac.
// ---------------------------------------------------------------------------

// Sentinel for nullable copyWith parameters that need to distinguish
// "keep current" (omit) from "set to null" (pass `null` explicitly).
const Object _kRoomInfoUnset = Object();

/// Snapshot of a single Pi room (one cwd / session).
class RoomInfo {
  final String roomId;
  final String? sessionId;
  final String? name;
  final String? cwd;
  final int startedAt;

  /// Plan 18 — display model the Pi-extension is running with (e.g.
  /// `claude-sonnet-4.5`, `gpt-4o`). Optional; Pi-ext may omit and
  /// the app falls back to `last paired` in the subtitle.
  final String? model;

  /// Plan/28 Wave D — current thinking level the Pi-extension session
  /// is running with. Optional; Pi-ext may omit when it cannot resolve
  /// it from the SDK, and legacy Pis don't publish this field at all.
  /// Drives the initial highlight of the Quick Actions thinking
  /// segmented control.
  final ThinkingLevel? thinking;

  /// Plan/32 — `true` when the room currently has an in-flight agent
  /// turn. The relay broadcasts `meta.working` for EVERY subscribed room
  /// (like presence), so Home can light the blue "working" dot on any
  /// session — not just the single connected one. Defaults to `false`
  /// (idle / not reported yet).
  final bool working;

  /// True while background subagents continue work beyond the current turn.
  /// This room-level axis is independent from [working].
  final bool background;

  const RoomInfo({
    required this.roomId,
    required this.startedAt,
    this.sessionId,
    this.name,
    this.cwd,
    this.model,
    this.thinking,
    this.working = false,
    this.background = false,
  });

  factory RoomInfo.fromJson(Map<String, dynamic> j) {
    final rawThinking = j['thinking'] as String?;
    return RoomInfo(
      roomId: j['room_id'] as String,
      sessionId: j['session_id'] as String?,
      name: j['name'] as String?,
      cwd: j['cwd'] as String?,
      startedAt: (j['started_at'] as num).toInt(),
      model: j['model'] as String?,
      thinking: rawThinking != null
          ? ThinkingLevel.fromWire(rawThinking)
          : null,
      working: (j['working'] as bool?) ?? false,
      background: (j['background'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'room_id': roomId,
    if (sessionId != null) 'session_id': sessionId,
    'name': name,
    'cwd': cwd,
    'started_at': startedAt,
    'model': model,
    if (thinking != null) 'thinking': thinking!.wire,
    'working': working,
    'background': background,
  };

  RoomInfo copyWith({
    Object? sessionId = _kRoomInfoUnset,
    String? name,
    String? cwd,
    int? startedAt,
    Object? model = _kRoomInfoUnset,
    Object? thinking = _kRoomInfoUnset,
    bool? working,
    bool? background,
  }) => RoomInfo(
    roomId: roomId,
    sessionId: identical(sessionId, _kRoomInfoUnset)
        ? this.sessionId
        : sessionId as String?,
    name: name ?? this.name,
    cwd: cwd ?? this.cwd,
    startedAt: startedAt ?? this.startedAt,
    model: identical(model, _kRoomInfoUnset) ? this.model : model as String?,
    thinking: identical(thinking, _kRoomInfoUnset)
        ? this.thinking
        : thinking as ThinkingLevel?,
    working: working ?? this.working,
    background: background ?? this.background,
  );

  @override
  bool operator ==(Object other) =>
      other is RoomInfo &&
      other.roomId == roomId &&
      other.sessionId == sessionId &&
      other.name == name &&
      other.cwd == cwd &&
      other.startedAt == startedAt &&
      other.model == model &&
      other.thinking == thinking &&
      other.working == working &&
      other.background == background;

  @override
  int get hashCode => Object.hash(
    roomId,
    sessionId,
    name,
    cwd,
    startedAt,
    model,
    thinking,
    working,
    background,
  );
}

class RoomAnnounced extends ControlInbound {
  final String peer;
  final String roomId;
  final String? sessionId;
  final String? name;
  final String? cwd;
  final int startedAt;

  /// Plan 18 — display model the Pi-extension is running with.
  final String? model;

  /// Plan/28 Wave D — current thinking level the Pi seeds at
  /// session start. Parsed from `meta.thinking` or top-level
  /// `thinking` depending on whether the relay flattens metadata.
  final ThinkingLevel? thinking;

  /// Plan/32 — in-flight agent turn at announce time. `null` when the
  /// frame omitted it (legacy relay); the ConnectionManager then keeps
  /// any previously-known value instead of forcing `false`.
  final bool? working;

  /// Background subagent activity at announcement time. Null means the
  /// announcing relay/extension omitted the optional field.
  final bool? background;
  const RoomAnnounced({
    required this.peer,
    required this.roomId,
    required this.startedAt,
    this.sessionId,
    this.name,
    this.cwd,
    this.model,
    this.thinking,
    this.working,
    this.background,
  });
}

class RoomEnded extends ControlInbound {
  final String peer;
  final String roomId;
  final int sinceTs;
  const RoomEnded({
    required this.peer,
    required this.roomId,
    required this.sinceTs,
  });
}

class RoomsSnapshot extends ControlInbound {
  final String peer;
  final List<RoomInfo> rooms;
  const RoomsSnapshot({required this.peer, required this.rooms});
}

/// Plan 18 — incremental update to a room's metadata (model is the
/// only field for now, but the `meta` envelope is open-ended). The
/// relay pushes this when the Pi-extension swaps its model
/// mid-session.
class RoomMetaUpdated extends ControlInbound {
  final String peer;
  final String roomId;
  final String? sessionId;
  final String? model;

  /// Plan/28 Wave D — current thinking level, parsed from
  /// `meta.thinking`. Null when the Pi only published a model change.
  /// The app treats both fields as independently optional so an update
  /// for only one of them doesn't clobber the other on the cache side.
  final ThinkingLevel? thinking;

  /// Plan/28 Wave D — `true` when the `meta` envelope carried a `model`
  /// key (even if value is null). Lets the ConnectionManager handler
  /// distinguish "model was not part of this update" from "model was
  /// explicitly cleared", which matters now that updates can be
  /// thinking-only.
  ///
  /// Defaults to `true` for ergonomic programmatic construction
  /// (callers / tests can pass `model: x` without also remembering
  /// the boolean). [RoomMetaUpdated.fromJson] passes the precise
  /// presence-of-key boolean instead.
  final bool hasModel;

  /// Plan/28 Wave D — same convention for `thinking`.
  final bool hasThinking;

  /// Same convention for opaque session id bootstrap metadata.
  final bool hasSessionId;

  /// Plan/32 — in-flight agent turn for this room. `null` = the update
  /// did not carry `working` (preserve the cached value); non-null =
  /// set. No separate `hasWorking` flag is needed because `working` can
  /// never be "explicitly null" on the wire — `false` is the off state.
  final bool? working;

  /// Background subagent activity. Null means the update omitted the field,
  /// so the ConnectionManager preserves the cached room value.
  final bool? background;

  const RoomMetaUpdated({
    required this.peer,
    required this.roomId,
    this.sessionId,
    this.model,
    this.thinking,
    this.working,
    this.background,
    this.hasModel = true,
    this.hasThinking = true,
    this.hasSessionId = true,
  });
}

// ---------------------------------------------------------------------------
// PresenceState — per-peer summary kept by ConnectionManager.
// ---------------------------------------------------------------------------

sealed class PresenceState {
  const PresenceState();
}

class PresenceUnknown extends PresenceState {
  const PresenceUnknown();
}

class PresenceOnline extends PresenceState {
  final int? sinceTs;
  const PresenceOnline({this.sinceTs});
}

class PresenceOffline extends PresenceState {
  final int? sinceTs;
  const PresenceOffline({this.sinceTs});
}

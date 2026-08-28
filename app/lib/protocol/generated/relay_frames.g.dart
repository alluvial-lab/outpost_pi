// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated from protocol/schema/relay-{outer,control}.schema.json.

const int relayDefaultMaxDecodedBytes = 4194304;
const int relayMaxFrameOverheadBytes = 65536;
const int relayMaxPreAuthFrameBytes = 16384;
const int relayMaxRawMessageBytes = 5657944;
const int relayMaxDeviceIdBytes = 128;
const int relayMaxRoomIdBytes = 256;
const int relayMaxRoomNameBytes = 256;
const int relayMaxCwdBytes = 4096;
const int relayMaxSessionIdBytes = 512;
const int relayMaxModelBytes = 256;
const int relayMaxThinkingBytes = 32;

sealed class RelayInboundFrameDto {
  const RelayInboundFrameDto();

  factory RelayInboundFrameDto.fromJson(Map<String, dynamic> json) {
    if (json['peer'] is String && json['ct'] is String && json['type'] == null) {
      return RelayOuterEnvelopeDto.fromJson(json);
    }
    return RelayServerControlFrameDto.fromJson(json);
  }
}

final class RelayOuterEnvelopeDto extends RelayInboundFrameDto {
  const RelayOuterEnvelopeDto({required this.peer, required this.room, required this.ct});
  final String peer;
  final String? room;
  final String ct;

  factory RelayOuterEnvelopeDto.fromJson(Map<String, dynamic> json) => RelayOuterEnvelopeDto(
        peer: json['peer'] as String,
        room: json['room'] as String?,
        ct: json['ct'] as String,
      );
}

sealed class RelayServerControlFrameDto extends RelayInboundFrameDto {
  const RelayServerControlFrameDto();
  String get type;

  factory RelayServerControlFrameDto.fromJson(Map<String, dynamic> json) => switch (json['type']) {
        'challenge' => RelayChallengeFrameDto.fromJson(json),
        'presence' => RelayPresenceFrameDto.fromJson(json),
        'peer_online' => RelayPeerOnlineFrameDto.fromJson(json),
        'peer_offline' => RelayPeerOfflineFrameDto.fromJson(json),
        'rooms' => RelayRoomsFrameDto.fromJson(json),
        'room_announced' => RelayRoomAnnouncedFrameDto.fromJson(json),
        'room_ended' => RelayRoomEndedFrameDto.fromJson(json),
        'room_meta_updated' => RelayRoomMetaUpdatedFrameDto.fromJson(json),
        final unknown => throw FormatException('unsupported relay server frame type: $unknown'),
      };
}

final class RelayChallengeFrameDto extends RelayServerControlFrameDto {
  const RelayChallengeFrameDto({required this.nonce});
  final String nonce;
  @override
  String get type => 'challenge';
  factory RelayChallengeFrameDto.fromJson(Map<String, dynamic> json) =>
      RelayChallengeFrameDto(nonce: json['nonce'] as String);
}

final class RelayPresenceStateDto {
  const RelayPresenceStateDto({required this.peer, required this.online, this.sinceTs});
  final String peer;
  final bool online;
  final int? sinceTs;
  factory RelayPresenceStateDto.fromJson(Map<String, dynamic> json) => RelayPresenceStateDto(
        peer: json['peer'] as String,
        online: json['online'] as bool,
        sinceTs: (json['since_ts'] as num?)?.toInt(),
      );
}

final class RelayPresenceFrameDto extends RelayServerControlFrameDto {
  const RelayPresenceFrameDto({required this.states});
  final List<RelayPresenceStateDto> states;
  @override
  String get type => 'presence';
  factory RelayPresenceFrameDto.fromJson(Map<String, dynamic> json) => RelayPresenceFrameDto(
        states: (json['states'] as List<dynamic>)
            .map((item) => RelayPresenceStateDto.fromJson((item as Map).cast<String, dynamic>()))
            .toList(),
      );
}

final class RelayPeerOnlineFrameDto extends RelayServerControlFrameDto {
  const RelayPeerOnlineFrameDto({required this.peer});
  final String peer;
  @override
  String get type => 'peer_online';
  factory RelayPeerOnlineFrameDto.fromJson(Map<String, dynamic> json) =>
      RelayPeerOnlineFrameDto(peer: json['peer'] as String);
}

final class RelayPeerOfflineFrameDto extends RelayServerControlFrameDto {
  const RelayPeerOfflineFrameDto({required this.peer, required this.sinceTs});
  final String peer;
  final int sinceTs;
  @override
  String get type => 'peer_offline';
  factory RelayPeerOfflineFrameDto.fromJson(Map<String, dynamic> json) => RelayPeerOfflineFrameDto(
        peer: json['peer'] as String,
        sinceTs: (json['since_ts'] as num).toInt(),
      );
}

final class RelayRoomMetaDto {
  const RelayRoomMetaDto({
    required this.roomId,
    required this.working,
    required this.startedAt,
    this.name,
    this.cwd,
    this.sessionId,
    this.model,
    this.thinking,
    this.background,
  });
  final String roomId;
  final String? name;
  final String? cwd;
  final String? sessionId;
  final String? model;
  final String? thinking;
  final bool? working;
  final bool? background;
  final int startedAt;
  factory RelayRoomMetaDto.fromJson(Map<String, dynamic> json) {
    final legacyMeta = json['meta'] is Map
        ? (json['meta'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return RelayRoomMetaDto(
      roomId: json['room_id'] as String,
      name: json['name'] as String?,
      cwd: json['cwd'] as String?,
      sessionId: (json['session_id'] as String?) ?? (legacyMeta['session_id'] as String?),
      model: json['model'] as String?,
      thinking: (json['thinking'] as String?) ?? (legacyMeta['thinking'] as String?),
      working: (json['working'] as bool?) ?? (legacyMeta['working'] as bool?),
      background: (json['background'] as bool?) ?? (legacyMeta['background'] as bool?),
      startedAt: (json['started_at'] as num).toInt(),
    );
  }
}

final class RelayRoomsFrameDto extends RelayServerControlFrameDto {
  const RelayRoomsFrameDto({required this.peer, required this.rooms});
  final String peer;
  final List<RelayRoomMetaDto> rooms;
  @override
  String get type => 'rooms';
  factory RelayRoomsFrameDto.fromJson(Map<String, dynamic> json) => RelayRoomsFrameDto(
        peer: json['peer'] as String,
        rooms: (json['rooms'] as List<dynamic>)
            .map((item) => RelayRoomMetaDto.fromJson((item as Map).cast<String, dynamic>()))
            .toList(),
      );
}

final class RelayRoomAnnouncedFrameDto extends RelayServerControlFrameDto {
  const RelayRoomAnnouncedFrameDto({required this.peer, required this.room});
  final String peer;
  final RelayRoomMetaDto room;
  @override
  String get type => 'room_announced';
  factory RelayRoomAnnouncedFrameDto.fromJson(Map<String, dynamic> json) =>
      RelayRoomAnnouncedFrameDto(peer: json['peer'] as String, room: RelayRoomMetaDto.fromJson(json));
}

final class RelayRoomEndedFrameDto extends RelayServerControlFrameDto {
  const RelayRoomEndedFrameDto({required this.peer, required this.roomId, required this.sinceTs});
  final String peer;
  final String roomId;
  final int sinceTs;
  @override
  String get type => 'room_ended';
  factory RelayRoomEndedFrameDto.fromJson(Map<String, dynamic> json) => RelayRoomEndedFrameDto(
        peer: json['peer'] as String,
        roomId: json['room_id'] as String,
        sinceTs: (json['since_ts'] as num).toInt(),
      );
}

final class RelayRoomMetaPatchDto {
  const RelayRoomMetaPatchDto({
    this.model,
    this.thinking,
    this.sessionId,
    this.working,
    this.background,
    required this.hasModel,
    required this.hasThinking,
    required this.hasSessionId,
  });
  final String? model;
  final String? thinking;
  final String? sessionId;
  final bool? working;
  final bool? background;
  final bool hasModel;
  final bool hasThinking;
  final bool hasSessionId;
  factory RelayRoomMetaPatchDto.fromJson(Map<String, dynamic> json) => RelayRoomMetaPatchDto(
        model: json['model'] as String?,
        thinking: json['thinking'] as String?,
        sessionId: json['session_id'] as String?,
        working: json['working'] as bool?,
        background: json['background'] as bool?,
        hasModel: json.containsKey('model'),
        hasThinking: json.containsKey('thinking'),
        hasSessionId: json.containsKey('session_id'),
      );
}

final class RelayRoomMetaUpdatedFrameDto extends RelayServerControlFrameDto {
  const RelayRoomMetaUpdatedFrameDto({required this.peer, required this.roomId, required this.meta});
  final String peer;
  final String roomId;
  final RelayRoomMetaPatchDto meta;
  @override
  String get type => 'room_meta_updated';
  factory RelayRoomMetaUpdatedFrameDto.fromJson(Map<String, dynamic> json) =>
      RelayRoomMetaUpdatedFrameDto(
        peer: json['peer'] as String,
        roomId: json['room_id'] as String,
        meta: RelayRoomMetaPatchDto.fromJson(
          json['meta'] is Map
              ? (json['meta'] as Map).cast<String, dynamic>()
              : const <String, dynamic>{},
        ),
      );
}

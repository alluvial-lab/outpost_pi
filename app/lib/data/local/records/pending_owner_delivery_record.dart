import 'package:app/domain/entities/pending_owner_delivery.dart';
import 'package:app/domain/session_state.dart';

/// Encode one versioned owner-delivery outbox row at the Hive boundary.
final class PendingOwnerDeliveryRecord {
  const PendingOwnerDeliveryRecord({
    required this.id,
    required this.peerEpk,
    required this.roomId,
    required this.targetSessionId,
    required this.text,
    required this.createdAtMs,
    required this.image,
    required this.awaitingPickup,
  });

  static const int version = 1;
  static const Set<String> _fields = <String>{
    'version',
    'id',
    'peer_epk',
    'room_id',
    'target_session_id',
    'text',
    'created_at_ms',
    'image',
    'awaiting_pickup',
  };

  final String id;
  final String peerEpk;
  final String roomId;
  final String? targetSessionId;
  final String text;
  final int createdAtMs;
  final MessageImage? image;
  final bool awaitingPickup;

  factory PendingOwnerDeliveryRecord.fromEntity(
    PendingOwnerDelivery delivery,
  ) => PendingOwnerDeliveryRecord(
    id: delivery.id,
    peerEpk: delivery.peerEpk,
    roomId: delivery.roomId,
    targetSessionId: delivery.targetSessionId,
    text: delivery.text,
    createdAtMs: delivery.createdAt.millisecondsSinceEpoch,
    image: delivery.image,
    awaitingPickup: delivery.awaitingPickup,
  );

  /// Decode a closed, versioned record and reject malformed durable state.
  ///
  /// Throws [FormatException] rather than silently dropping recovery intent.
  factory PendingOwnerDeliveryRecord.fromJson(Map<String, dynamic> json) {
    if (json.keys.any((key) => !_fields.contains(key))) {
      throw const FormatException('Unknown owner-delivery outbox field');
    }
    if (json['version'] != version) {
      throw const FormatException('Unsupported owner-delivery outbox version');
    }
    final id = _nonEmpty(json, 'id');
    final peerEpk = _nonEmpty(json, 'peer_epk');
    final roomId = _nonEmpty(json, 'room_id');
    final target = json['target_session_id'];
    if (target != null && (target is! String || target.isEmpty)) {
      throw const FormatException('Malformed owner-delivery target session');
    }
    final text = json['text'];
    if (text is! String) {
      throw const FormatException('Malformed owner-delivery text');
    }
    final created = json['created_at_ms'];
    if (created is! num ||
        !created.isFinite ||
        created != created.truncate() ||
        created < 0) {
      throw const FormatException('Malformed owner-delivery timestamp');
    }

    MessageImage? image;
    final imageRaw = json['image'];
    if (imageRaw != null) {
      if (imageRaw is! Map) {
        throw const FormatException('Malformed owner-delivery image');
      }
      final imageJson = imageRaw.cast<Object?, Object?>();
      if (imageJson.keys.any((key) => key != 'data' && key != 'mime')) {
        throw const FormatException('Unknown owner-delivery image field');
      }
      final data = imageJson['data'];
      final mime = imageJson['mime'];
      if (data is! String || data.isEmpty || mime is! String || mime.isEmpty) {
        throw const FormatException('Malformed owner-delivery image');
      }
      image = MessageImage(data: data, mime: mime);
    }

    final awaitingPickup = json['awaiting_pickup'];
    if (awaitingPickup is! bool) {
      throw const FormatException('Malformed owner-delivery pickup state');
    }
    if (text.isEmpty && image == null) {
      throw const FormatException('Owner delivery needs text or an image');
    }

    return PendingOwnerDeliveryRecord(
      id: id,
      peerEpk: peerEpk,
      roomId: roomId,
      targetSessionId: target as String?,
      text: text,
      createdAtMs: created.toInt(),
      image: image,
      awaitingPickup: awaitingPickup,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'id': id,
    'peer_epk': peerEpk,
    'room_id': roomId,
    'target_session_id': targetSessionId,
    'text': text,
    'created_at_ms': createdAtMs,
    if (image != null)
      'image': <String, dynamic>{'data': image!.data, 'mime': image!.mime},
    'awaiting_pickup': awaitingPickup,
  };

  PendingOwnerDelivery toEntity() => PendingOwnerDelivery(
    id: id,
    peerEpk: peerEpk,
    roomId: roomId,
    targetSessionId: targetSessionId,
    text: text,
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
    image: image,
    awaitingPickup: awaitingPickup,
  );

  static String _nonEmpty(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Malformed owner-delivery field: $key');
  }
}

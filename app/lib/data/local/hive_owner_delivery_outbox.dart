import 'dart:convert';

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/pending_owner_delivery_record.dart';
import 'package:app/domain/contracts/owner_delivery_outbox.dart';
import 'package:app/domain/entities/pending_owner_delivery.dart';
import 'package:crypto/crypto.dart';

/// Store recoverable owner prompts in the app's common encrypted Hive box.
final class HiveOwnerDeliveryOutbox implements OwnerDeliveryOutbox {
  const HiveOwnerDeliveryOutbox(this._boxes);

  final LocalBoxes _boxes;

  @override
  Future<void> upsert(PendingOwnerDelivery delivery) async {
    final record = PendingOwnerDeliveryRecord.fromEntity(delivery);
    // Round-trip validation keeps programmatic callers behind the same strict
    // boundary as records loaded after a process restart.
    final json = record.toJson();
    PendingOwnerDeliveryRecord.fromJson(json);
    await _boxes.ownerDeliveryOutboxBox().put(_key(delivery), json);
  }

  @override
  Future<List<PendingOwnerDelivery>> listForRoom({
    required String peerEpk,
    required String roomId,
  }) async {
    final deliveries = <PendingOwnerDelivery>[];
    for (final value in _boxes.ownerDeliveryOutboxBox().values) {
      final delivery = _decode(value).toEntity();
      if (delivery.peerEpk == peerEpk && delivery.roomId == roomId) {
        deliveries.add(delivery);
      }
    }
    deliveries.sort((left, right) {
      final byCreation = left.createdAt.compareTo(right.createdAt);
      return byCreation == 0 ? left.id.compareTo(right.id) : byCreation;
    });
    return List<PendingOwnerDelivery>.unmodifiable(deliveries);
  }

  @override
  Future<void> removeConfirmed({
    required String id,
    required String confirmedSessionId,
  }) async {
    final box = _boxes.ownerDeliveryOutboxBox();
    final keys = <dynamic>[];
    for (final key in box.keys) {
      final delivery = _decode(box.get(key)).toEntity();
      if (delivery.id == id && delivery.targetSessionId == confirmedSessionId) {
        keys.add(key);
      }
    }
    if (keys.isNotEmpty) await box.deleteAll(keys);
  }

  PendingOwnerDeliveryRecord _decode(dynamic value) {
    if (value is Map<String, dynamic>) {
      return PendingOwnerDeliveryRecord.fromJson(value);
    }
    if (value is Map) {
      return PendingOwnerDeliveryRecord.fromJson(
        value.map((key, value) {
          if (key is! String) {
            throw const FormatException(
              'Owner-delivery outbox keys must be strings',
            );
          }
          return MapEntry(key, value);
        }),
      );
    }
    throw FormatException(
      'Unsupported owner-delivery outbox value: ${value.runtimeType}',
    );
  }

  static String _key(PendingOwnerDelivery delivery) => sha256
      .convert(
        utf8.encode(
          jsonEncode(<String>[delivery.peerEpk, delivery.roomId, delivery.id]),
        ),
      )
      .toString();
}

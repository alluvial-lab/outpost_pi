import 'package:app/data/local/legacy_projection_import.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/local/records/transcript_event_record.dart';
import 'package:app/data/local/transcript_box_identity.dart';
import 'package:app/data/transport/epk_encoding.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/domain/session_state.dart';
import 'package:hive/hive.dart';

/// Observe one completed migration mutation for deterministic crash tests.
typedef TranscriptMigrationCheckpointHook = Future<void> Function();

/// Summarize one completed legacy transcript migration.
final class TranscriptMigrationReport {
  const TranscriptMigrationReport({
    required this.sessions,
    required this.events,
    required this.importedProjectionRows,
    required this.deletedLegacyBoxes,
  });

  final int sessions;
  final int events;
  final int importedProjectionRows;
  final int deletedLegacyBoxes;
}

/// Report a stable fail-closed legacy transcript migration error.
final class TranscriptMigrationException implements Exception {
  const TranscriptMigrationException({
    required this.code,
    required this.sourceBox,
  });

  final String code;
  final String sourceBox;

  @override
  String toString() => 'TranscriptMigrationException($code, $sourceBox)';
}

/// Copy, verify, and remove indexed plaintext transcript boxes at bootstrap.
///
/// The legacy index is the migration manifest. Every destination is verified
/// before any source is deleted, the manifest is deleted last, and the version
/// marker is written only after deletion succeeds.
final class TranscriptStorageMigrator {
  TranscriptStorageMigrator({
    required HiveCipher cipher,
    TranscriptMigrationCheckpointHook? afterDestinationWrite,
    TranscriptMigrationCheckpointHook? afterSourceDelete,
  }) : _cipher = cipher,
       _afterDestinationWrite = afterDestinationWrite,
       _afterSourceDelete = afterSourceDelete;

  static const String metadataBoxName = 'transcript_security_meta';
  static const String migrationVersionKey = 'migration_version';
  static const String copyVerifiedKey = 'migration_copy_verified_v3';
  static const int migrationVersion = 3;
  static const String legacyIndexBoxName = 'sessions_index';

  final HiveCipher _cipher;
  final TranscriptMigrationCheckpointHook? _afterDestinationWrite;
  final TranscriptMigrationCheckpointHook? _afterSourceDelete;

  /// Whether the plaintext-to-v3 migration has completed.
  static bool isComplete(Box<dynamic> metadata) =>
      metadata.get(migrationVersionKey) == migrationVersion;

  /// Derive the exact normalized legacy event-log name for [ref].
  static String legacyEventsBoxName(RemoteSessionRef ref) =>
      'transcript_events_${_legacyTuple(ref)}'.toLowerCase();

  /// Derive the exact normalized legacy message-projection name for [ref].
  static String legacyMessagesBoxName(RemoteSessionRef ref) =>
      'msgs_${_legacyTuple(ref)}'.toLowerCase();

  /// Migrate all canonical sessions represented by [legacyIndex].
  ///
  /// Throws [TranscriptMigrationException] without deleting a source when any
  /// record is malformed, ambiguously attributed, or conflicts with a partial
  /// destination from an earlier attempt.
  Future<TranscriptMigrationReport> migrate({
    required Box<dynamic> legacyIndex,
    required Box<dynamic> secureIndex,
    required Box<dynamic> metadata,
  }) async {
    if (isComplete(metadata)) {
      return const TranscriptMigrationReport(
        sessions: 0,
        events: 0,
        importedProjectionRows: 0,
        deletedLegacyBoxes: 0,
      );
    }

    final candidates = _readCandidates(legacyIndex);
    if (metadata.get(copyVerifiedKey) == true) {
      final deleted = await _deleteVerifiedSources(
        candidates: candidates,
        legacyIndex: legacyIndex,
        metadata: metadata,
      );
      return TranscriptMigrationReport(
        sessions: candidates.length,
        events: 0,
        importedProjectionRows: 0,
        deletedLegacyBoxes: deleted,
      );
    }

    final eventsBySession = <String, Map<String, Map<String, Object?>>>{
      for (final candidate in candidates)
        candidate.key: <String, Map<String, Object?>>{},
    };
    final canonicalEventCounts = <String, int>{
      for (final candidate in candidates) candidate.key: 0,
    };

    final eventGroups = _groupBy(
      candidates,
      (candidate) => legacyEventsBoxName(candidate.record.ref),
    );
    for (final entry in eventGroups.entries) {
      if (!await Hive.boxExists(entry.key)) continue;
      final source = await _openLegacy(entry.key);
      for (final sourceKey in source.keys) {
        final record = _readEventRecord(source.get(sourceKey), entry.key);
        if (sourceKey is! String || sourceKey != record.eventId) {
          throw TranscriptMigrationException(
            code: 'malformed_legacy_event',
            sourceBox: entry.key,
          );
        }
        final matches = entry.value
            .where(
              (candidate) => candidate.record.sessionId == record.sessionId,
            )
            .toList(growable: false);
        if (matches.length != 1) {
          throw TranscriptMigrationException(
            code: matches.isEmpty
                ? 'unattributed_legacy_event'
                : 'ambiguous_legacy_event',
            sourceBox: entry.key,
          );
        }
        final candidate = matches.single;
        _addExpectedEvent(
          eventsBySession[candidate.key]!,
          record.toJson(),
          entry.key,
        );
        canonicalEventCounts[candidate.key] =
            canonicalEventCounts[candidate.key]! + 1;
      }
    }

    var importedProjectionRows = 0;
    final projectionGroups = _groupBy(
      candidates,
      (candidate) => legacyMessagesBoxName(candidate.record.ref),
    );
    for (final entry in projectionGroups.entries) {
      if (!await Hive.boxExists(entry.key)) continue;
      final source = await _openLegacy(entry.key);
      final rows = _readProjectionRows(source, entry.key);
      if (rows.isEmpty) continue;

      if (entry.value.length != 1) {
        final candidateWithoutEvents = entry.value.any(
          (candidate) => canonicalEventCounts[candidate.key] == 0,
        );
        if (candidateWithoutEvents) {
          throw TranscriptMigrationException(
            code: 'ambiguous_legacy_projection',
            sourceBox: entry.key,
          );
        }
        continue;
      }

      final candidate = entry.value.single;
      if (canonicalEventCounts[candidate.key] != 0) continue;
      try {
        final imported = LegacyProjectionImport.toEvents(
          session: candidate.transcriptKey,
          rows: rows,
        );
        for (var sequence = 0; sequence < imported.length; sequence += 1) {
          _addExpectedEvent(
            eventsBySession[candidate.key]!,
            TranscriptEventRecord.fromEvent(
              imported[sequence],
              sequence,
            ).toJson(),
            entry.key,
          );
        }
      } on FormatException {
        throw TranscriptMigrationException(
          code: 'malformed_legacy_projection',
          sourceBox: entry.key,
        );
      }
      importedProjectionRows += rows.length;
    }

    final destinationBoxes = <String, Box<dynamic>>{};
    for (final candidate in candidates) {
      final expected = eventsBySession[candidate.key]!;
      final destinationName = TranscriptBoxIdentity.eventsName(
        candidate.transcriptKey,
      );
      if (expected.isEmpty && !await Hive.boxExists(destinationName)) continue;
      final destination = await _openEncrypted(destinationName);
      destinationBoxes[candidate.key] = destination;
      await _copyExpected(destination, expected, destinationName);
      _verifyExact(destination, expected, destinationName);
    }

    for (final candidate in candidates) {
      final expected = candidate.record.toJson();
      final key = candidate.record.key;
      if (secureIndex.containsKey(key)) {
        if (!_deepEquals(secureIndex.get(key), expected)) {
          throw const TranscriptMigrationException(
            code: 'destination_conflict',
            sourceBox: 'sessions_index_v3',
          );
        }
      } else {
        await secureIndex.put(key, expected);
        await _afterDestinationWrite?.call();
      }
    }

    for (final candidate in candidates) {
      final destination = destinationBoxes[candidate.key];
      if (destination != null) {
        _verifyExact(
          destination,
          eventsBySession[candidate.key]!,
          destination.name,
        );
      }
      final expectedIndex = candidate.record.toJson();
      if (!_deepEquals(secureIndex.get(candidate.record.key), expectedIndex)) {
        throw const TranscriptMigrationException(
          code: 'destination_verification_failed',
          sourceBox: 'sessions_index_v3',
        );
      }
    }

    await metadata.put(copyVerifiedKey, true);
    final deleted = await _deleteVerifiedSources(
      candidates: candidates,
      legacyIndex: legacyIndex,
      metadata: metadata,
    );

    return TranscriptMigrationReport(
      sessions: candidates.length,
      events: eventsBySession.values.fold<int>(
        0,
        (count, events) => count + events.length,
      ),
      importedProjectionRows: importedProjectionRows,
      deletedLegacyBoxes: deleted,
    );
  }

  static String _legacyTuple(RemoteSessionRef ref) =>
      '${_legacySafe(toAppEpk(ref.peerEpk))}__${_legacySafe(ref.roomId)}__${_legacySafe(ref.sessionId)}';

  static String _legacySafe(String value) => value
      .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');

  List<_MigrationCandidate> _readCandidates(Box<dynamic> legacyIndex) {
    final byKey = <String, _MigrationCandidate>{};
    for (final value in legacyIndex.values) {
      try {
        final json = _stringMap(value);
        final record = SessionIndexRecord.fromJson(json);
        if (record.epk.isEmpty ||
            record.roomId.isEmpty ||
            record.sessionId.isEmpty) {
          throw const FormatException('Legacy index identity is empty');
        }
        final candidate = _MigrationCandidate(record);
        final existing = byKey[candidate.key];
        if (existing != null && existing.record != record) {
          throw TranscriptMigrationException(
            code: 'conflicting_legacy_index',
            sourceBox: legacyIndex.name,
          );
        }
        byKey[candidate.key] = candidate;
      } on TranscriptMigrationException {
        rethrow;
      } on Object {
        throw TranscriptMigrationException(
          code: 'malformed_legacy_index',
          sourceBox: legacyIndex.name,
        );
      }
    }
    return byKey.values.toList(growable: false);
  }

  Map<String, List<_MigrationCandidate>> _groupBy(
    List<_MigrationCandidate> candidates,
    String Function(_MigrationCandidate candidate) boxName,
  ) {
    final groups = <String, List<_MigrationCandidate>>{};
    for (final candidate in candidates) {
      groups.putIfAbsent(boxName(candidate), () => []).add(candidate);
    }
    return groups;
  }

  Future<Box<dynamic>> _openLegacy(String name) async {
    try {
      return await Hive.openBox<dynamic>(name, crashRecovery: false);
    } on Object {
      throw TranscriptMigrationException(
        code: 'legacy_source_unreadable',
        sourceBox: name,
      );
    }
  }

  Future<Box<dynamic>> _openEncrypted(String name) async {
    try {
      return await Hive.openBox<dynamic>(
        name,
        encryptionCipher: _cipher,
        crashRecovery: false,
      );
    } on Object {
      throw TranscriptMigrationException(
        code: 'destination_unreadable',
        sourceBox: name,
      );
    }
  }

  TranscriptEventRecord _readEventRecord(Object? value, String sourceBox) {
    try {
      return TranscriptEventRecord.fromJson(_objectMap(value));
    } on Object {
      throw TranscriptMigrationException(
        code: 'malformed_legacy_event',
        sourceBox: sourceBox,
      );
    }
  }

  List<MessageRecord> _readProjectionRows(
    Box<dynamic> source,
    String sourceBox,
  ) {
    final rows = <MessageRecord>[];
    final ids = <String>{};
    try {
      for (final key in source.keys) {
        if (key is! int) {
          throw const FormatException('Projection key must be int');
        }
        final json = _stringMap(source.get(key));
        _validateProjectionJson(json, key);
        final row = MessageRecord.fromJson(json);
        if (!ids.add(row.id)) {
          throw const FormatException('Projection message ids must be unique');
        }
        rows.add(row);
      }
      rows.sort((left, right) {
        final bySequence = left.seq.compareTo(right.seq);
        return bySequence == 0 ? left.id.compareTo(right.id) : bySequence;
      });
      return rows;
    } on Object {
      throw TranscriptMigrationException(
        code: 'malformed_legacy_projection',
        sourceBox: sourceBox,
      );
    }
  }

  void _validateProjectionJson(Map<String, dynamic> json, int key) {
    final id = json['id'];
    final sequence = json['seq'];
    final role = json['role'];
    final timestamp = json['ts'];
    if (id is! String ||
        id.isEmpty ||
        sequence is! num ||
        sequence.toInt() != sequence ||
        sequence.toInt() != key ||
        role is! String ||
        !MsgRole.values.any((item) => item.name == role) ||
        timestamp is! num ||
        timestamp.toInt() != timestamp) {
      throw const FormatException('Malformed legacy projection row');
    }
    final pending = json['pending'];
    if (pending != null && pending is! bool) {
      throw const FormatException('Malformed legacy pending state');
    }
    final status = json['status'];
    if (status != null &&
        (status is! String ||
            !UserMsgStatus.values.any((item) => item.name == status))) {
      throw const FormatException('Malformed legacy user status');
    }
    if (role == MsgRole.tool.name) {
      final tool = json['tool'];
      if (tool is! Map) throw const FormatException('Legacy tool data missing');
      final toolJson = _stringMap(tool);
      final toolStatus = toolJson['status'];
      if (toolStatus is! String ||
          !ToolEventStatus.values.any((item) => item.name == toolStatus)) {
        throw const FormatException('Malformed legacy tool status');
      }
    }
  }

  void _addExpectedEvent(
    Map<String, Map<String, Object?>> expected,
    Map<String, Object?> record,
    String sourceBox,
  ) {
    final eventId = record['event_id'];
    if (eventId is! String) {
      throw TranscriptMigrationException(
        code: 'malformed_legacy_event',
        sourceBox: sourceBox,
      );
    }
    final existing = expected[eventId];
    if (existing != null && !_deepEquals(existing, record)) {
      throw TranscriptMigrationException(
        code: 'destination_conflict',
        sourceBox: sourceBox,
      );
    }
    expected[eventId] = record;
  }

  Future<void> _copyExpected(
    Box<dynamic> destination,
    Map<String, Map<String, Object?>> expected,
    String destinationName,
  ) async {
    for (final entry in expected.entries) {
      if (destination.containsKey(entry.key)) {
        if (!_deepEquals(destination.get(entry.key), entry.value)) {
          throw TranscriptMigrationException(
            code: 'destination_conflict',
            sourceBox: destinationName,
          );
        }
      } else {
        await destination.put(entry.key, entry.value);
        await _afterDestinationWrite?.call();
      }
      if (!_deepEquals(destination.get(entry.key), entry.value)) {
        throw TranscriptMigrationException(
          code: 'destination_verification_failed',
          sourceBox: destinationName,
        );
      }
    }
  }

  void _verifyExact(
    Box<dynamic> destination,
    Map<String, Map<String, Object?>> expected,
    String destinationName,
  ) {
    if (destination.length != expected.length) {
      throw TranscriptMigrationException(
        code: 'destination_conflict',
        sourceBox: destinationName,
      );
    }
    for (final entry in expected.entries) {
      if (!_deepEquals(destination.get(entry.key), entry.value)) {
        throw TranscriptMigrationException(
          code: 'destination_verification_failed',
          sourceBox: destinationName,
        );
      }
    }
  }

  Future<int> _deleteVerifiedSources({
    required List<_MigrationCandidate> candidates,
    required Box<dynamic> legacyIndex,
    required Box<dynamic> metadata,
  }) async {
    final sourceNames = <String>{
      for (final candidate in candidates)
        legacyEventsBoxName(candidate.record.ref),
      for (final candidate in candidates)
        legacyMessagesBoxName(candidate.record.ref),
    };
    var deleted = 0;
    for (final sourceName in sourceNames) {
      if (!await Hive.boxExists(sourceName)) continue;
      await _deleteLegacy(sourceName);
      deleted += 1;
      await _afterSourceDelete?.call();
    }
    await legacyIndex.deleteFromDisk();
    deleted += 1;
    await _afterSourceDelete?.call();
    await metadata.delete(copyVerifiedKey);
    await metadata.put(migrationVersionKey, migrationVersion);
    return deleted;
  }

  Future<void> _deleteLegacy(String name) async {
    try {
      await Hive.deleteBoxFromDisk(name);
    } on Object {
      throw TranscriptMigrationException(
        code: 'legacy_source_delete_failed',
        sourceBox: name,
      );
    }
  }
}

final class _MigrationCandidate {
  const _MigrationCandidate(this.record);

  final SessionIndexRecord record;
  String get key => record.key;
  TranscriptSessionKey get transcriptKey => TranscriptSessionKey(
    peerId: record.epk,
    roomId: record.roomId,
    sessionId: record.sessionId,
  );
}

Map<String, dynamic> _stringMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) {
      if (key is! String) {
        throw const FormatException('Map keys must be strings');
      }
      return MapEntry(key, value);
    });
  }
  throw const FormatException('Value must be an object');
}

Map<String, Object?> _objectMap(Object? value) {
  final map = _stringMap(value);
  return map.map((key, value) => MapEntry(key, value as Object?));
}

bool _deepEquals(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_deepEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (!_deepEquals(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

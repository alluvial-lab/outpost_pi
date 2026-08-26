import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:cockpit/app/core/data/storage/json_state_store.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;

/// Classify a legacy-store export failure without retaining user content.
enum LegacyHiveMigrationDiagnostic { storeExportFailed }

/// Receive a closed migration category and one canonical store name.
typedef LegacyHiveMigrationDiagnosticSink =
    void Function(LegacyHiveMigrationDiagnostic diagnostic, String storeName);

/// Report whether this invocation committed a one-shot legacy migration.
final class LegacyMigrationResult {
  const LegacyMigrationResult({required this.ran, required this.failedStores});

  /// Whether this invocation wrote the marker-last migration commit.
  final bool ran;

  /// Known stores that were isolated to an empty JSON envelope.
  final List<String> failedStores;
}

/// Export installed Hive state into independent atomic JSON stores once.
///
/// The marker is written last, source boxes are never removed, and one failed
/// store cannot discard successful exports from the other known stores.
final class LegacyHiveMigrator {
  const LegacyHiveMigrator({
    required this.stateDirectory,
    required this.legacyDirectories,
    this.openAttempts = 10,
    this.retryDelay = const Duration(milliseconds: 300),
    this.diagnostics = _logDiagnostic,
  });

  /// Canonical set of Cockpit stores with installed Hive compatibility state.
  static const List<String> storeNames = <String>[
    'settings',
    'window_state',
    'projects',
    'layouts',
  ];

  /// Idempotence commit written only after every destination is complete.
  static const String markerFileName = 'migration.json';

  static const int _markerVersion = 1;
  static const String _emptyEnvelope = '{"version":1,"data":{}}';

  final String stateDirectory;
  final List<String> legacyDirectories;
  final int openAttempts;
  final Duration retryDelay;
  final LegacyHiveMigrationDiagnosticSink diagnostics;

  /// Export the first legacy directory when no migration marker exists.
  ///
  /// A second invocation skips without opening Hive or rewriting JSON state.
  Future<LegacyMigrationResult> runIfNeeded() async {
    if (openAttempts < 1) {
      throw ArgumentError.value(
        openAttempts,
        'openAttempts',
        'Must be positive',
      );
    }

    final marker = File(p.join(stateDirectory, markerFileName));
    if (await marker.exists()) {
      return const LegacyMigrationResult(ran: false, failedStores: <String>[]);
    }

    final sourceDirectory = await _findSourceDirectory();
    final failedStores = <String>[];
    if (sourceDirectory != null) {
      var hiveReady = true;
      try {
        Hive.init(sourceDirectory);
      } catch (_) {
        hiveReady = false;
      }

      for (final String storeName in storeNames) {
        var contents = _emptyEnvelope;
        final source = File(p.join(sourceDirectory, '$storeName.hive'));
        if (await source.exists()) {
          try {
            if (!hiveReady) throw StateError('legacy_init_failed');
            contents = await _exportStore(storeName);
          } catch (_) {
            failedStores.add(storeName);
            diagnostics(
              LegacyHiveMigrationDiagnostic.storeExportFailed,
              storeName,
            );
          }
        }
        await JsonStateStore.writeAtomic(
          File(p.join(stateDirectory, '$storeName.json')),
          contents,
        );
      }
    }

    await JsonStateStore.writeAtomic(
      marker,
      jsonEncode(<String, Object?>{
        'version': _markerVersion,
        'source': sourceDirectory == null ? 'none' : 'legacy_hive',
        'failedStores': failedStores,
      }),
    );
    return LegacyMigrationResult(
      ran: true,
      failedStores: List<String>.unmodifiable(failedStores),
    );
  }

  Future<String?> _findSourceDirectory() async {
    for (final String candidate in legacyDirectories) {
      for (final String storeName in storeNames) {
        if (await File(p.join(candidate, '$storeName.hive')).exists()) {
          return candidate;
        }
      }
    }
    return null;
  }

  Future<String> _exportStore(String storeName) async {
    final box = await _openBoxWithRetry(storeName);
    try {
      return JsonStateStore.encodeEnvelope(_normalizeMap(box.toMap()));
    } finally {
      await box.close();
    }
  }

  Future<Box<dynamic>> _openBoxWithRetry(String name) async {
    for (var attempt = 1; attempt <= openAttempts; attempt++) {
      try {
        return await Hive.openBox<dynamic>(name);
      } on FileSystemException {
        if (attempt == openAttempts) rethrow;
        if (retryDelay > Duration.zero) {
          await Future<void>.delayed(retryDelay);
        }
      }
    }
    throw StateError('Legacy Hive retry exhausted without a result');
  }

  static Map<String, Object?> _normalizeMap(Map<dynamic, dynamic> source) =>
      <String, Object?>{
        for (final MapEntry<dynamic, dynamic> entry in source.entries)
          '${entry.key}': _normalizeValue(entry.value),
      };

  static Object? _normalizeValue(Object? value) {
    if (value is Map<dynamic, dynamic>) return _normalizeMap(value);
    if (value is List<dynamic>) {
      return value.map<Object?>(_normalizeValue).toList(growable: false);
    }
    return value;
  }

  static void _logDiagnostic(
    LegacyHiveMigrationDiagnostic diagnostic,
    String storeName,
  ) {
    developer.log(
      'migration category=${diagnostic.name} store=$storeName',
      name: 'cockpit.legacy-hive-migration',
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:cockpit/app/core/domain/contracts/state_store.dart';
import 'package:path/path.dart' as p;

/// Classify JSON state failures without retaining paths, payloads, or errors.
enum JsonStateStoreDiagnostic {
  emptyFile,
  malformedJson,
  invalidEnvelope,
  unsupportedVersion,
  readFailure,
  quarantineFailure,
}

/// Receive a content-free JSON state diagnostic.
typedef JsonStateStoreDiagnosticSink =
    void Function(JsonStateStoreDiagnostic diagnostic);

/// Replace one state file with a complete serialized envelope.
typedef JsonStateStoreAtomicWriter =
    Future<void> Function(File file, String contents);

/// Own versioned, atomic JSON stores rooted below one directory.
///
/// Instance caching and flush lifecycle are factory-local, so tests and
/// composition roots do not depend on process-global storage state.
final class JsonStateStoreFactory implements StateStoreFactory {
  JsonStateStoreFactory(
    String rootDirectory, {
    JsonStateStoreAtomicWriter? atomicWriter,
    JsonStateStoreDiagnosticSink? diagnostics,
  }) : _rootDirectory = p.normalize(Directory(rootDirectory).absolute.path),
       _atomicWriter = atomicWriter ?? JsonStateStore.writeAtomic,
       _diagnostics = diagnostics ?? _logDiagnostic;

  final String _rootDirectory;
  final JsonStateStoreAtomicWriter _atomicWriter;
  final JsonStateStoreDiagnosticSink _diagnostics;
  final Map<String, JsonStateStore> _stores = <String, JsonStateStore>{};

  @override
  Future<StateStore> open(String name) async {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'Must be a simple store name');
    }
    final path = p.normalize(p.join(_rootDirectory, '$name.json'));
    final existing = _stores[path];
    if (existing != null) return existing;

    final file = File(path);
    final loaded = await JsonStateStore._load(file, _diagnostics);
    final store = JsonStateStore._(
      file,
      Map<String, Object?>.of(loaded.data),
      atomicWriter: _atomicWriter,
      writesAllowed: loaded.writesAllowed,
    );
    _stores[path] = store;
    return store;
  }

  @override
  Future<void> flushAll() =>
      Future.wait(_stores.values.map((JsonStateStore store) => store.flush()));

  static void _logDiagnostic(JsonStateStoreDiagnostic diagnostic) {
    developer.log(
      'state recovery category=${diagnostic.name}',
      name: 'cockpit.json-state-store',
    );
  }
}

/// Keep one small key/value document in memory and persist complete snapshots.
///
/// Reads tolerate corrupt or unsupported files by quarantining the original and
/// opening empty. Writes are serialized, debounced, and committed through a
/// same-directory temporary file followed by an atomic rename.
final class JsonStateStore implements StateStore {
  JsonStateStore._(
    this._file,
    this._data, {
    required JsonStateStoreAtomicWriter atomicWriter,
    required bool writesAllowed,
  }) : _atomicWriter = atomicWriter,
       _writesAllowed = writesAllowed;

  /// Version of the JSON envelope persisted on disk.
  static const int formatVersion = 1;

  /// Coalescing window for bursts of small state changes.
  static const Duration debounceWindow = Duration(milliseconds: 150);

  static const List<Duration> _renameBackoff = <Duration>[
    Duration.zero,
    Duration(milliseconds: 100),
    Duration(milliseconds: 250),
  ];

  final File _file;
  final Map<String, Object?> _data;
  final JsonStateStoreAtomicWriter _atomicWriter;
  final bool _writesAllowed;

  Timer? _debounce;
  Completer<void>? _pending;
  Future<void> _writeTail = Future<void>.value();
  int _revision = 0;
  int _queuedRevision = 0;
  int _persistedRevision = 0;

  @override
  Object? get(String key) => _data[key];

  @override
  Iterable<String> get keys => _data.keys;

  @override
  Iterable<Object?> get values => _data.values;

  @override
  Future<void> put(String key, Object? value) {
    final normalized = _normalizeJsonValue(value);
    _data[key] = normalized;
    return _scheduleWrite();
  }

  @override
  Future<void> putAll(Map<String, Object?> entries) {
    final normalized = <String, Object?>{
      for (final MapEntry<String, Object?> entry in entries.entries)
        entry.key: _normalizeJsonValue(entry.value),
    };
    _data.addAll(normalized);
    return _scheduleWrite();
  }

  @override
  Future<void> delete(String key) {
    _data.remove(key);
    return _scheduleWrite();
  }

  @override
  Future<void> flush() async {
    _debounce?.cancel();
    if (_pending != null) _commitPending();

    try {
      await _writeTail;
    } catch (_) {
      // The mutation future already reports its failed attempt. Flush gets one
      // fresh attempt at the newest snapshot before it reports a durable error.
    }

    if (_persistedRevision < _revision && _queuedRevision < _revision) {
      final retry = _pending ??= Completer<void>();
      unawaited(
        retry.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      _commitPending();
      await _writeTail;
    }
  }

  Future<void> _scheduleWrite() {
    _revision++;
    final pending = _pending ??= Completer<void>();
    _debounce?.cancel();
    _debounce = Timer(debounceWindow, _commitPending);
    return pending.future;
  }

  void _commitPending() {
    final pending = _pending;
    if (pending == null) return;
    _pending = null;
    _debounce?.cancel();

    final revision = _revision;
    final contents = jsonEncode(<String, Object?>{
      'version': formatVersion,
      'data': _data,
    });
    _queuedRevision = revision;
    final previous = _writeTail;
    final attempt = () async {
      try {
        await previous;
      } catch (_) {
        // A failed older snapshot must not poison newer persistence attempts.
      }
      if (!_writesAllowed) {
        throw const FileSystemException(
          'state recovery category=quarantineFailure',
        );
      }
      await _atomicWriter(_file, contents);
      if (revision > _persistedRevision) _persistedRevision = revision;
    }();
    _writeTail = attempt;
    attempt.then<void>(
      (_) {
        if (!pending.isCompleted) pending.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_queuedRevision == revision) {
          _queuedRevision = _persistedRevision;
        }
        if (!pending.isCompleted) pending.completeError(error, stackTrace);
      },
    );
  }

  static Object? _normalizeJsonValue(Object? value) {
    try {
      return jsonDecode(jsonEncode(value));
    } on JsonUnsupportedObjectError {
      throw ArgumentError.value(
        value.runtimeType,
        'value',
        'Must be JSON-compatible',
      );
    }
  }

  static Future<_LoadedState> _load(
    File file,
    JsonStateStoreDiagnosticSink diagnostics,
  ) async {
    if (!await file.exists()) {
      return const _LoadedState(<String, Object?>{}, writesAllowed: true);
    }

    JsonStateStoreDiagnostic? failure;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        failure = JsonStateStoreDiagnostic.emptyFile;
      } else {
        Object? decoded;
        try {
          decoded = jsonDecode(raw);
        } on FormatException {
          failure = JsonStateStoreDiagnostic.malformedJson;
        }
        if (failure == null) {
          if (decoded is! Map<String, dynamic>) {
            failure = JsonStateStoreDiagnostic.invalidEnvelope;
          } else if (decoded['version'] != formatVersion) {
            failure = JsonStateStoreDiagnostic.unsupportedVersion;
          } else if (decoded['data'] is! Map<String, dynamic>) {
            failure = JsonStateStoreDiagnostic.invalidEnvelope;
          } else {
            return _LoadedState(
              Map<String, Object?>.from(
                decoded['data'] as Map<String, dynamic>,
              ),
              writesAllowed: true,
            );
          }
        }
      }
    } on FileSystemException {
      failure = JsonStateStoreDiagnostic.readFailure;
    }

    diagnostics(failure);
    final quarantined = await _quarantine(file);
    if (!quarantined) diagnostics(JsonStateStoreDiagnostic.quarantineFailure);
    return _LoadedState(<String, Object?>{}, writesAllowed: quarantined);
  }

  static Future<bool> _quarantine(File file) async {
    for (var suffix = 0; suffix < 100; suffix++) {
      final ending = suffix == 0 ? '.corrupt' : '.corrupt.$suffix';
      final target = File('${file.path}$ending');
      try {
        if (await target.exists()) continue;
        await file.rename(target.path);
        return true;
      } on FileSystemException {
        return false;
      }
    }
    return false;
  }

  /// Replace [file] with [contents] through a flushed same-directory temp file.
  ///
  /// The temp file is explicitly flushed before rename. Rename retries cover
  /// bounded transient filesystem locks; an exhausted attempt throws and leaves
  /// the old destination or temp evidence intact rather than reporting success.
  static Future<void> writeAtomic(File file, String contents) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    final output = await temporary.open(mode: FileMode.write);
    try {
      await output.writeFrom(utf8.encode(contents));
      await output.flush();
    } finally {
      await output.close();
    }

    FileSystemException? lastError;
    for (final Duration backoff in _renameBackoff) {
      if (backoff > Duration.zero) await Future<void>.delayed(backoff);
      try {
        await temporary.rename(file.path);
        return;
      } on FileSystemException catch (error) {
        lastError = error;
      }
    }
    throw lastError!;
  }
}

final class _LoadedState {
  const _LoadedState(this.data, {required this.writesAllowed});

  final Map<String, Object?> data;
  final bool writesAllowed;
}

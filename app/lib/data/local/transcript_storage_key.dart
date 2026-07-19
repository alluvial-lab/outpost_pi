import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

/// Persist the encoded transcript encryption key outside Hive storage.
abstract interface class TranscriptKeyValueStore {
  Future<String?> read();
  Future<void> write(String encodedKey);
}

/// Store the transcript encryption key in the platform secure store.
final class SecureTranscriptKeyValueStore implements TranscriptKeyValueStore {
  SecureTranscriptKeyValueStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'transcript_storage_key_v3';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String encodedKey) =>
      _storage.write(key: _key, value: encodedKey);
}

/// Load or provision the single AES-256 key shared by transcript-bearing boxes.
final class TranscriptStorageKeyManager {
  TranscriptStorageKeyManager(this._store);

  final TranscriptKeyValueStore _store;
  Future<Uint8List>? _inflight;

  /// Return the validated key, generating it only for an unprovisioned install.
  Future<Uint8List> loadOrCreate({required bool keyWasProvisioned}) {
    final inflight = _inflight;
    if (inflight != null) return inflight;
    final future = _loadOrCreate(keyWasProvisioned: keyWasProvisioned);
    _inflight = future;
    return future;
  }

  Future<Uint8List> _loadOrCreate({required bool keyWasProvisioned}) async {
    final stored = await _store.read();
    if (stored != null) return _decode(stored);
    if (keyWasProvisioned) {
      throw const TranscriptStorageKeyException('missing_provisioned_key');
    }

    final encoded = base64Encode(Hive.generateSecureKey());
    await _store.write(encoded);
    final persisted = await _store.read();
    if (persisted == null) {
      throw const TranscriptStorageKeyException('key_write_not_persisted');
    }
    return _decode(persisted);
  }

  Uint8List _decode(String encoded) {
    try {
      final decoded = base64Decode(encoded);
      if (decoded.length != 32) {
        throw const TranscriptStorageKeyException('malformed_key');
      }
      return Uint8List.fromList(decoded);
    } on FormatException {
      throw const TranscriptStorageKeyException('malformed_key');
    }
  }
}

/// Report a stable fail-closed transcript key or cipher initialization error.
final class TranscriptStorageKeyException implements Exception {
  const TranscriptStorageKeyException(this.code);

  final String code;

  @override
  String toString() => 'TranscriptStorageKeyException($code)';
}

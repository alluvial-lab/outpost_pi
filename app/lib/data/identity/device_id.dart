import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Per-install device identifier, persisted in secure storage.
///
/// Used in the relay `hello` frame so the relay can close prior conn(s) from
/// the **same device** on duplicate auth — a reconnect (wifi→cellular leaves
/// the old TCP path half-open) tears down the old socket immediately instead
/// of waiting for the 25 s WS ping to time it out. Two genuine devices of the
/// same Owner (shared Ed25519 key via iCloud Keychain / Block Store) present
/// **different** `device_id`s and coexist — see
/// `story-relay-close-same-device-duplicate-auth`.
///
/// Generated once on first access, then cached in memory + persisted. Secure
/// storage is cleared on uninstall, which is correct — a reinstall is a new
/// device identity.
class DeviceId {
  static const _key = 'device_id';

  final FlutterSecureStorage _store;
  String? _cached;

  DeviceId([FlutterSecureStorage? store])
    : _store = store ?? const FlutterSecureStorage();

  /// Returns the per-install device id, generating + persisting one on first
  /// call. Idempotent — repeated calls return the same value.
  Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;

    final stored = await _store.read(key: _key);
    if (stored != null && stored.isNotEmpty) {
      _cached = stored;
      return stored;
    }

    final generated = _generate();
    await _store.write(key: _key, value: generated);
    _cached = generated;
    return generated;
  }

  /// Cryptographically-random 128-bit id, base16-encoded (32 chars). Not a
  /// UUID per se — no version/variant bits needed since this is never parsed,
  /// only compared for equality by the relay.
  String _generate() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

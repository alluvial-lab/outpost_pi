import 'package:app/domain/contracts/dismissed_update_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persist the dismissed update version in its own [FlutterSecureStorage] key.
///
/// This shares the app's existing secure store with pairing and preferences but
/// stores only the version string, without serialization.
class SecureDismissedUpdateStore implements DismissedUpdateStore {
  SecureDismissedUpdateStore([FlutterSecureStorage? store])
    : _store = store ?? const FlutterSecureStorage();

  final FlutterSecureStorage _store;

  static const String _key = 'update.dismissed_version';

  @override
  Future<String?> dismissedVersion() async {
    final raw = await _store.read(key: _key);
    return (raw != null && raw.isNotEmpty) ? raw : null;
  }

  @override
  Future<void> dismiss(String version) =>
      _store.write(key: _key, value: version);
}

import 'package:cockpit/app/cockpit/domain/contracts/dismissed_update_store.dart';
import 'package:cockpit/app/core/domain/contracts/state_store.dart';

/// Persist the dismissed update version through the settings state store.
final class JsonDismissedUpdateStore implements DismissedUpdateStore {
  JsonDismissedUpdateStore(this._store);

  static const String _key = 'dismissed_update_version';

  final StateStore _store;

  @override
  String? dismissedVersion() {
    final raw = _store.get(_key);
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  @override
  Future<void> dismiss(String version) => _store.put(_key, version);
}

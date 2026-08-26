import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/contracts/state_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';

/// Persist application preferences through the shared state-store boundary.
final class JsonSettingsStore implements SettingsStore {
  JsonSettingsStore(this._store);

  /// Named state document shared with settings-scoped values.
  static const String storeName = 'settings';

  static const String _key = 'app';

  final StateStore _store;

  @override
  Future<AppSettings> load() async {
    final raw = _store.get(_key);
    if (raw is Map<dynamic, dynamic>) return AppSettings.fromJson(raw);
    return const AppSettings();
  }

  @override
  Future<void> save(AppSettings settings) =>
      _store.put(_key, settings.toJson());
}

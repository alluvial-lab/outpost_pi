import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:hive/hive.dart';

/// Persist [AppSettings] in a Hive box.
///
/// Stores one JSON record under [_key] using primitive values only, so no Hive
/// type adapters are required.
class HiveSettingsStore implements SettingsStore {
  HiveSettingsStore(this._box);

  final Box<dynamic> _box;

  static const String boxName = 'settings';
  static const String _key = 'app';

  @override
  Future<AppSettings> load() async {
    final raw = _box.get(_key);
    if (raw is Map) return AppSettings.fromJson(raw);
    return const AppSettings();
  }

  @override
  Future<void> save(AppSettings settings) => _box.put(_key, settings.toJson());
}

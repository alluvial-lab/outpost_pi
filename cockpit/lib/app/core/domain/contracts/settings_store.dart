import 'package:cockpit/app/core/domain/entities/app_settings.dart';

/// Persist [AppSettings] through a domain-owned storage contract.
///
/// The Hive adapter lives in `data/`, keeping persistence details out of the
/// callers that load and update application preferences.
abstract class SettingsStore {
  /// Load saved preferences, or defaults when no settings have been saved.
  Future<AppSettings> load();

  /// Persist the current preferences.
  Future<void> save(AppSettings settings);
}

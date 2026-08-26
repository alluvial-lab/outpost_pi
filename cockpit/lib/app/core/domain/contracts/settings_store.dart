import 'package:cockpit/app/core/domain/entities/app_settings.dart';

/// Persist [AppSettings] through a domain-owned storage contract.
///
/// Concrete persistence stays in `data/`, keeping backend details out of the
/// callers that load and update application preferences.
abstract class SettingsStore {
  /// Load saved preferences, or defaults when no settings have been saved.
  Future<AppSettings> load();

  /// Persist the current preferences.
  Future<void> save(AppSettings settings);
}

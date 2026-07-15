import 'package:cockpit/app/core/domain/contracts/system_permissions.dart';
import 'package:cockpit/app/core/domain/entities/setup_check.dart';
import 'package:flutter/foundation.dart';

/// Manage operating-system notification permission for the **Notifications** tab.
///
/// This page-scoped ViewModel exposes permission checks and requests through
/// [SystemPermissions]. Persisted notification enablement remains owned by
/// `SettingsController`.
class NotificationsViewModel extends ChangeNotifier {
  NotificationsViewModel(this._perms);

  final SystemPermissions _perms;

  CheckStatus _status = CheckStatus.checking;
  bool _disposed = false;

  CheckStatus get status => _status;

  /// Probe current permission when the tab mounts or the window regains focus.
  Future<void> check() => _set(_perms.notificationStatus);

  /// Request permission, send a test notification, and return the result.
  Future<CheckStatus> request() async {
    await _set(_perms.requestNotifications);
    return _status;
  }

  Future<void> _set(Future<CheckStatus> Function() probe) async {
    final result = await probe();
    if (_disposed) return;
    _status = result;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

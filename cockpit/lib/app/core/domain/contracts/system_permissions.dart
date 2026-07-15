import 'package:cockpit/app/core/domain/entities/setup_check.dart';

/// Expose the OS permissions Cockpit needs, with macOS as the primary target.
///
/// The notification-plugin and disk-heuristic adapter lives in `data/`. On
/// platforms where a permission does not exist or apply, methods return
/// [CheckStatus.notApplicable].
abstract class SystemPermissions {
  /// Read the current notification permission status.
  Future<CheckStatus> notificationStatus();

  /// Request notification permission and send a test notification.
  ///
  /// Returns the status after the request completes.
  Future<CheckStatus> requestNotifications();
}

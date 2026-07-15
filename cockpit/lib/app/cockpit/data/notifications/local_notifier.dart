import 'package:cockpit/app/cockpit/domain/contracts/notifier.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Deliver native desktop notifications through `flutter_local_notifications`.
///
/// Configuration is macOS-first while retaining the Linux adapter path.
class LocalNotifier implements Notifier {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  int _id = 0;

  @override
  Future<void> init() async {
    const settings = InitializationSettings(
      macOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        // Cockpit normally remains in the foreground; without these flags,
        // UNUserNotificationCenter silently suppresses the banner.
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
      ),
      linux: LinuxInitializationSettings(defaultActionName: 'Open'),
    );
    await _plugin.initialize(settings);
  }

  @override
  Future<void> agentFinished({
    required String agentName,
    required String workspace,
  }) async {
    final subtitle = workspace.isEmpty ? agentName : '$agentName · $workspace';
    await _plugin.show(
      _id++,
      'Agent finished',
      subtitle,
      const NotificationDetails(
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        linux: LinuxNotificationDetails(),
      ),
    );
  }
}

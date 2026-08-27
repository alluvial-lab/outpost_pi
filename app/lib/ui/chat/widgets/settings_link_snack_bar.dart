import 'package:flutter/material.dart';

/// Launch the platform application-settings surface.
typedef AppSettingsLauncher = Future<void> Function();

/// Build permission feedback with an actionable application-settings link.
SnackBar buildSettingsLinkSnackBar({
  required String message,
  required AppSettingsLauncher openSettings,
}) {
  return SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 5),
    behavior: SnackBarBehavior.floating,
    action: SnackBarAction(label: 'Settings', onPressed: openSettings),
  );
}

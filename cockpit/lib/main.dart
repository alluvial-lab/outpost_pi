import 'dart:io';

import 'package:cockpit/config/dependencies.dart';
import 'package:cockpit/routing/router.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupDependencies();
  await _setupWindow();
  runApp(CockpitApp(router: buildRouter()));
}

/// Esconde a barra nativa (temos a customizada). macOS/Windows/Linux.
Future<void> _setupWindow() async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    // Esconde os botões nativos do macOS — usamos os nossos desenhados.
    windowButtonVisibility: false,
    minimumSize: Size(720, 480),
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

class CockpitApp extends StatelessWidget {
  const CockpitApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Cockpit',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      routerConfig: router,
    );
  }
}

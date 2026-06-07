import 'dart:io';

import 'package:cockpit/config/dependencies.dart';
import 'package:cockpit/domain/entities/app_settings.dart';
import 'package:cockpit/routing/router.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:cockpit/ui/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupDependencies();
  // Preferências carregadas ANTES do primeiro frame → o app já abre no tema
  // salvo (sem flash de tema errado).
  final settings = buildSettingsController();
  await settings.load();
  await _setupWindow();
  runApp(CockpitApp(router: buildRouter(), settings: settings));
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
  const CockpitApp({super.key, required this.router, required this.settings});

  final GoRouter router;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    // O controller fica ACIMA do MaterialApp → trocar tema/fonte repinta tudo,
    // e a tela de Configurações o consome via Provider.
    return ChangeNotifierProvider<SettingsController>.value(
      value: settings,
      child: Consumer<SettingsController>(
        builder: (context, controller, _) {
          final s = controller.settings;
          // "Tamanho da interface" = **zoom do app inteiro** (texto, panes,
          // ícones, app bar, terminal). Baseline 14 = 1.0x. Ver [_AppZoom].
          final uiScale = s.interfaceSize / 14.0;
          return MaterialApp.router(
            title: 'Cockpit',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(brightness: Brightness.light, settings: s),
            darkTheme: buildTheme(brightness: Brightness.dark, settings: s),
            themeMode: _themeMode(s.themeMode),
            routerConfig: router,
            builder: (context, child) => CallbackShortcuts(
              // Zoom por teclado: ⌘=/⌘- (macOS) · Ctrl+=/Ctrl+- (Win/Linux);
              // ⌘0/Ctrl+0 reseta. CallbackShortcuts é aditivo (não quebra
              // copiar/colar) e funciona mesmo com um input focado.
              bindings: _zoomBindings(controller),
              child: _AppZoom(scale: uiScale, child: child ?? const SizedBox()),
            ),
          );
        },
      ),
    );
  }

  ThemeMode _themeMode(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  /// Atalhos de zoom (tamanho da interface). `meta` = ⌘ (macOS); `control` =
  /// Ctrl (Windows/Linux). `=`/numpad+ aumenta, `-`/numpad- diminui, `0` reseta.
  /// Step de 1, limitado a 11..22 (igual ao stepper das Configurações).
  Map<ShortcutActivator, VoidCallback> _zoomBindings(
    SettingsController controller,
  ) {
    void by(double delta) {
      final next = (controller.settings.interfaceSize + delta).clamp(11.0, 22.0);
      controller.setInterfaceSize(next);
    }

    void reset() => controller.setInterfaceSize(14);

    return <ShortcutActivator, VoidCallback>{
      for (final mod in const [true, false]) ...{
        SingleActivator(
          LogicalKeyboardKey.equal,
          meta: mod,
          control: !mod,
        ): () => by(1),
        SingleActivator(
          LogicalKeyboardKey.numpadAdd,
          meta: mod,
          control: !mod,
        ): () => by(1),
        SingleActivator(
          LogicalKeyboardKey.minus,
          meta: mod,
          control: !mod,
        ): () => by(-1),
        SingleActivator(
          LogicalKeyboardKey.numpadSubtract,
          meta: mod,
          control: !mod,
        ): () => by(-1),
        SingleActivator(
          LogicalKeyboardKey.digit0,
          meta: mod,
          control: !mod,
        ): reset,
      },
    };
  }
}

/// Zoom do **app inteiro**: lê o app num espaço lógico reduzido (`size/scale`) e
/// escala de volta com `Transform`, então tudo (texto, ícones, panes, app bar)
/// cresce junto — não só o texto. Vetores (texto/ícones) são re-rasterizados
/// pelo Skia (nítidos); bitmaps (imagens) interpolam. `scale == 1` é no-op.
class _AppZoom extends StatelessWidget {
  const _AppZoom({required this.scale, required this.child});
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if ((scale - 1.0).abs() < 0.001) return child;
    final mq = MediaQuery.of(context);
    final scaled = mq.size / scale;
    return MediaQuery(
      // Layout pensa numa tela menor (`size/scale`) → os elementos ocupam mais
      // dela; o `FittedBox` amplia pro tamanho real da janela. Uso FittedBox (e
      // não `Transform.scale` cru) porque ele **reporta o tamanho da janela** —
      // o Transform reportaria o tamanho lógico reduzido e um ancestral cortaria
      // a direita/baixo (Files e composer somindo). Gestos/hit-test são
      // convertidos pro espaço lógico automaticamente.
      data: mq.copyWith(size: scaled),
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: scaled.width,
          height: scaled.height,
          child: child,
        ),
      ),
    );
  }
}

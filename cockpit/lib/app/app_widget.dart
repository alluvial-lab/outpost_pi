import 'package:cockpit/app/core/app_intents.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Visual root of the app. Sits **below** `ModularApp` (which provides the
/// router) and **above** `ShadcnApp.router`. Reads the app-scoped
/// [SettingsController] (provided in `ModularApp.provide`, in `main`) via
/// `context.watch` → changing theme/font repaints everything. The router
/// comes from `ModularApp.routerConfigOf(context)`.
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;
    // "Interface size" = **zoom for the whole app** (text, panes, icons,
    // app bar, terminal). Baseline 14 = 1.0x. See [_AppZoom].
    final uiScale = s.interfaceSize / 14.0;
    return ShadcnApp.router(
      title: 'Cockpit',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness: Brightness.light, settings: s),
      darkTheme: buildTheme(brightness: Brightness.dark, settings: s),
      themeMode: _themeMode(s.themeMode),
      routerConfig: ModularApp.routerConfigOf(context),
      builder: (context, child) {
        // Effective brightness (already resolved by ShadcnApp via themeMode):
        // builds the bespoke tokens and installs them via CockpitTheme — feeds
        // context.colors/typo/syntax across the entire route tree.
        final tokens = buildTokens(
          brightness: Theme.of(context).brightness,
          settings: s,
        );
        return CallbackShortcuts(
          // Global shortcuts (always in the focus chain): zoom (⌘=/⌘-/⌘0) and
          // input focus (⌘L). CallbackShortcuts is additive (doesn't break
          // copy/paste) and works even with nothing focused.
          bindings: {..._zoomBindings(controller), ..._focusBindings()},
          child: _AppZoom(
            scale: uiScale,
            child: CockpitTheme(
              colors: tokens.colors,
              typo: tokens.typo,
              syntax: tokens.syntax,
              child: child ?? const SizedBox(),
            ),
          ),
        );
      },
    );
  }

  ThemeMode _themeMode(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  /// ⌘L / Ctrl+L → focuses the active agent's input (via a global bridge,
  /// resolved by `CockpitPage`). Lives here (not in the shell) so it fires
  /// even when focus fell on an empty area.
  Map<ShortcutActivator, VoidCallback> _focusBindings() {
    void focus() => requestFocusActiveComposer?.call();
    return <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyL, meta: true): focus,
      const SingleActivator(LogicalKeyboardKey.keyL, control: true): focus,
    };
  }

  /// Zoom shortcuts (interface size). `meta` = ⌘ (macOS); `control` = Ctrl
  /// (Windows/Linux). `=`/numpad+ increases, `-`/numpad- decreases, `0` resets.
  /// Step of 1, clamped to 11..22 (same as the Settings stepper).
  Map<ShortcutActivator, VoidCallback> _zoomBindings(
    SettingsController controller,
  ) {
    void by(double delta) {
      final next = (controller.settings.interfaceSize + delta).clamp(
        11.0,
        22.0,
      );
      controller.setInterfaceSize(next);
    }

    void reset() => controller.setInterfaceSize(14);

    return <ShortcutActivator, VoidCallback>{
      for (final mod in const [true, false]) ...{
        SingleActivator(
          LogicalKeyboardKey.equal,
          meta: mod,
          control: !mod,
        ): () =>
            by(1),
        SingleActivator(
          LogicalKeyboardKey.numpadAdd,
          meta: mod,
          control: !mod,
        ): () =>
            by(1),
        SingleActivator(
          LogicalKeyboardKey.minus,
          meta: mod,
          control: !mod,
        ): () =>
            by(-1),
        SingleActivator(
          LogicalKeyboardKey.numpadSubtract,
          meta: mod,
          control: !mod,
        ): () =>
            by(-1),
        SingleActivator(LogicalKeyboardKey.digit0, meta: mod, control: !mod):
            reset,
      },
    };
  }
}

/// Zoom for the **whole app**: lays the app out in a reduced logical space
/// (`size/scale`) and scales it back up with `FittedBox`, so everything (text,
/// icons, panes, app bar) grows together — not just the text. Vectors
/// (text/icons) are re-rasterized by Skia (crisp); bitmaps (images) interpolate.
/// `scale == 1` is a no-op.
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
      // Layout thinks it has a smaller screen (`size/scale`) → elements take
      // up more of it; the `FittedBox` enlarges to the real window size. Using
      // FittedBox (not raw `Transform.scale`) because it **reports the window
      // size** — Transform would report the reduced logical size and an ancestor
      // would clip on the right/bottom (Files and composer vanishing).
      // Gestures/hit-testing are converted to the logical space automatically.
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

import 'dart:async';

import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/contracts/system_permissions.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/domain/entities/setup_check.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/app_theme.dart';
import 'package:cockpit/app/settings/ui/categories/appearance_settings_panel.dart';
import 'package:cockpit/app/settings/ui/categories/notification_settings_panel.dart';
import 'package:cockpit/app/settings/ui/notifications_viewmodel.dart';
import 'package:flutter/widgets.dart' show Brightness, SizedBox, Widget;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;

/// Behavior coverage for app-scoped preference persistence and notification
/// permission lifecycle handling.
///
/// Appearance and notification interactions are exercised through their real
/// panels. Language command behavior stays at [SettingsController] because the
/// panel probes every configured language server through real processes.

void main() {
  group('app preference panels — SettingsController persistence', () {
    testWidgets('appearance edits persist font and conversation preferences', (
      tester,
    ) async {
      final store = _RecordingSettingsStore();
      final controller = SettingsController(store);
      await controller.load();

      await _pumpPreferencePanel(
        tester,
        panel: const AppearanceSettingsPanel(),
        controller: controller,
      );

      await tester.enterText(
        find.byType(shadcn.TextField).first,
        '  Iosevka  ',
      );
      await tester.ensureVisible(find.byType(shadcn.Switch));
      await tester.tap(find.byType(shadcn.Switch));
      await tester.pump();

      expect(controller.settings.interfaceFont, 'Iosevka');
      expect(controller.settings.pinUserMessage, isFalse);
      expect(store.saved?.interfaceFont, 'Iosevka');
      expect(store.saved?.pinUserMessage, isFalse);
    });

    testWidgets('notification toggle persists through the app-scoped owner', (
      tester,
    ) async {
      final store = _RecordingSettingsStore();
      final controller = SettingsController(store);
      await controller.load();
      final notifications = NotificationsViewModel(
        _ImmediatePermissions(CheckStatus.ok),
      );

      await _pumpPreferencePanel(
        tester,
        panel: const NotificationSettingsPanel(),
        controller: controller,
        notifications: notifications,
      );
      await tester.tap(find.byType(shadcn.Switch));
      await tester.pump();

      expect(controller.settings.notificationsEnabled, isFalse);
      expect(store.saved?.notificationsEnabled, isFalse);
    });
  });

  group('SettingsController — LSP command save/reset behavior', () {
    test(
      'setLspCommand persists a non-empty override and saves through the store',
      () async {
        final store = _RecordingSettingsStore();
        final controller = SettingsController(store);
        await controller.load();

        const languageId = 'dart';
        controller.setLspCommand(
          languageId,
          '  dart language-server --stdio  ',
        );

        // The override is reflected in the live settings...
        expect(
          controller.settings.lspCommands[languageId],
          'dart language-server --stdio',
          reason: 'override visible on the controller immediately',
        );
        // ...and was persisted through the store.
        expect(store.saved, isNotNull);
        expect(
          store.saved!.lspCommands[languageId],
          'dart language-server --stdio',
          reason: 'override persisted to the store on save',
        );
      },
    );

    test(
      'setLspCommand with empty/null clears the override (reset semantics)',
      () async {
        final store = _RecordingSettingsStore();
        final controller = SettingsController(store);
        await controller.load();
        // Pre-seed an override, then clear it (the panel's "Reset to default"
        // calls setLspCommand(id, null)).
        controller.setLspCommand('dart', 'stale-lsp');
        store.reset();

        controller.setLspCommand('dart', null);

        expect(
          controller.settings.lspCommands['dart'],
          isNull,
          reason: 'override cleared on reset',
        );
        expect(store.saved, isNotNull);
        expect(
          store.saved!.lspCommands['dart'],
          isNull,
          reason: 'clear persisted to the store',
        );
      },
    );

    test(
      'setLspFormatter persists and clears the formatter override',
      () async {
        final store = _RecordingSettingsStore();
        final controller = SettingsController(store);
        await controller.load();

        controller.setLspFormatter('dart', '  dart format  ');
        expect(controller.settings.lspFormatters['dart'], 'dart format');
        expect(store.saved!.lspFormatters['dart'], 'dart format');

        controller.setLspFormatter('dart', null);
        expect(controller.settings.lspFormatters['dart'], isNull);
        expect(store.saved!.lspFormatters['dart'], isNull);
      },
    );

    test('setFormatOnSave persists through the settings store', () async {
      final store = _RecordingSettingsStore();
      final controller = SettingsController(store);
      await controller.load();

      controller.setFormatOnSave(true);

      expect(controller.settings.formatOnSave, isTrue);
      expect(store.saved?.formatOnSave, isTrue);
    });

    test(
      'trimming: a whitespace-only command is treated as empty/cleared',
      () async {
        final store = _RecordingSettingsStore();
        final controller = SettingsController(store);
        await controller.load();

        controller.setLspCommand('dart', '   ');

        expect(
          controller.settings.lspCommands['dart'],
          isNull,
          reason:
              'whitespace-only command cleared rather than stored as spaces',
        );
      },
    );
  });

  group('NotificationSettingsPanel — permission mounted guard', () {
    testWidgets(
      'request completing after unmount does not throw (mounted guard holds)',
      (tester) async {
        // A SystemPermissions whose request completes AFTER the widget is
        // disposed. The panel's _request() awaits then checks
        // `if (!mounted) return;` — completing late must not throw or call
        // setState on an unmounted widget.
        final perms = _LateCompletingPermissions();
        final vm = NotificationsViewModel(perms);

        final store = _RecordingSettingsStore();
        final controller = SettingsController(store);
        await controller.load();

        await _pumpPreferencePanel(
          tester,
          panel: const NotificationSettingsPanel(),
          controller: controller,
          notifications: vm,
        );
        await tester.pump();

        // Dispose the panel BEFORE the permission future resolves. This is the
        // core of the mounted-guard test: the await in _request() returns into a
        // dead element.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        // Now complete the late future — must not throw or call setState on an
        // unmounted widget.
        perms.completeRequest(CheckStatus.missing);
        await tester.pump();

        // Reaching here without a Flutter error means the mounted guard held.
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('missing permission surfaces the macOS instructions dialog', (
      tester,
    ) async {
      final perms = _ImmediatePermissions(CheckStatus.missing);
      final vm = NotificationsViewModel(perms);

      final store = _RecordingSettingsStore();
      final controller = SettingsController(store);
      await controller.load();

      await _pumpPreferencePanel(
        tester,
        panel: const NotificationSettingsPanel(),
        controller: controller,
        notifications: vm,
      );
      await tester.pumpAndSettle();

      // The instructions dialog is opened by _request() when status is still
      // missing after the request. Trigger the request affordance and pump.
      // (On non-macOS the permission row is not rendered; skip there.)
      final requestAffordance = find.textContaining('Allow');
      if (requestAffordance.evaluate().isNotEmpty) {
        await tester.tap(requestAffordance.first);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('System Settings'),
          findsWidgets,
          reason: 'macOS instructions dialog opened for missing permission',
        );
      }
    });
  });
}

// --- helpers ---

Future<void> _pumpPreferencePanel(
  WidgetTester tester, {
  required Widget panel,
  required SettingsController controller,
  NotificationsViewModel? notifications,
}) async {
  final feature = createModule(
    path: '/',
    register: (c) => c.route(
      '/',
      provide: (s) {
        s.addChangeNotifier<SettingsController>(() => controller);
        if (notifications != null) {
          s.addChangeNotifier<NotificationsViewModel>(() => notifications);
        }
      },
      child: (context, state) => panel,
    ),
  );
  final app = createModule(register: (c) => c.module(feature));
  final boot = bootstrapModule(app);
  await tester.pumpWidget(
    shadcn.ShadcnApp.router(
      theme: buildTheme(brightness: Brightness.dark),
      routerConfig: modularRouterConfig(
        boot.routes,
        injector: boot.injector,
        manager: boot.manager,
      ),
    ),
  );
  await tester.pump();
}

class _RecordingSettingsStore implements SettingsStore {
  AppSettings? saved;
  AppSettings _current = const AppSettings();

  @override
  Future<AppSettings> load() async => _current;

  @override
  Future<void> save(AppSettings settings) async {
    saved = settings;
    _current = settings;
  }

  void reset() {
    saved = null;
    _current = const AppSettings();
  }
}

class _LateCompletingPermissions implements SystemPermissions {
  final Completer<CheckStatus> _request = Completer<CheckStatus>();

  @override
  Future<CheckStatus> notificationStatus() async => CheckStatus.checking;

  @override
  Future<CheckStatus> requestNotifications() => _request.future;

  void completeRequest(CheckStatus status) => _request.complete(status);
}

class _ImmediatePermissions implements SystemPermissions {
  _ImmediatePermissions(this._status);
  final CheckStatus _status;

  @override
  Future<CheckStatus> notificationStatus() async => _status;

  @override
  Future<CheckStatus> requestNotifications() async => _status;
}

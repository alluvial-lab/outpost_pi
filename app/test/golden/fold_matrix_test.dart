import 'dart:io';

import 'package:app/data/local/boxes.dart';
import 'package:app/ui/chat/chat_page.dart';
import 'package:app/ui/chat/quick_actions/viewmodels/quick_actions_viewmodel.dart';
import 'package:app/ui/chat/quick_actions/widgets/quick_actions_sheet.dart';
import 'package:app/ui/chat/widgets/attach_sheet.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/onboarding/onboarding_page.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';
import 'package:app/ui/pairing/widgets/paste_qr_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import 'fold_matrix_capture.dart';
import 'fold_matrix_fixtures.dart';

const _typedPairingUri =
    'outpostpi://pair?t=AAAAAAAAAAAAAAAAAAAAAA&'
    'epk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&'
    'rm=outpost-app&n=Studio%20MacBook%20Pro';

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    final goldenDirectory = foldGoldenDirectory();
    if (goldenDirectory.existsSync()) {
      goldenDirectory.deleteSync(recursive: true);
    }
    hiveDirectory = Directory(
      '${Directory.current.path}/.dart_tool/fold_matrix_hive',
    );
    if (hiveDirectory.existsSync()) hiveDirectory.deleteSync(recursive: true);
    hiveDirectory.createSync(recursive: true);
    await LocalBoxes.initForTest(hiveDirectory.path);
  });

  tearDownAll(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) hiveDirectory.deleteSync(recursive: true);
  });

  testWidgets(
    'writes the complete Pixel Fold render-evidence matrix',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final geometry in foldGeometries) {
        // ignore: avoid_print
        print('GEO ${geometry.suffix} configure begin');
        await configureFoldView(tester, geometry);
        // ignore: avoid_print
        print('GEO ${geometry.suffix} fixture begin');
        final fixture =
            await tester.runAsync<FoldMatrixFixture>(FoldMatrixFixture.create);
        if (fixture == null) {
          fail('fold matrix fixture failed to build under runAsync');
        }
        // ignore: avoid_print
        print('GEO ${geometry.suffix} fixture done');
        try {
          await _capture(
            tester,
            geometry: geometry,
            surface: 'home',
            home: fixture.homeSurface(),
          );
          await _capture(
            tester,
            geometry: geometry,
            surface: 'two-pane-shell',
            home: fixture.shellSurface(),
          );
          await _capture(
            tester,
            geometry: geometry,
            surface: 'chat',
            home: fixture.chatSurface(),
          );
          await _capture(
            tester,
            geometry: geometry,
            surface: 'chat-keyboard',
            keyboardInset: 280,
            home: fixture.chatSurface(),
            afterPump: () async {
              final field = find.byType(TextField).first;
              await tester.tap(field, warnIfMissed: false);
              await tester.pump(const Duration(milliseconds: 120));
            },
          );
          await _captureQuickActions(tester, fixture, geometry);
          await _captureAttachSheet(tester, fixture, geometry);
          await _capture(
            tester,
            geometry: geometry,
            surface: 'onboarding-relay',
            home: fixture.onboardingSurface(OnboardingStep.relay),
            settleFor: const Duration(milliseconds: 360),
          );
          await _capture(
            tester,
            geometry: geometry,
            surface: 'onboarding-pair',
            home: fixture.onboardingSurface(OnboardingStep.pair),
            settleFor: const Duration(milliseconds: 360),
          );
          await _capturePasteSheet(tester, fixture, geometry);
          await _capture(
            tester,
            geometry: geometry,
            surface: 'sync-required',
            home: fixture.syncRequiredSurface(),
          );
          await _capture(
            tester,
            geometry: geometry,
            surface: 'storage-recovery',
            home: fixture.storageRecoverySurface(),
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 20));
          await fixture.dispose();
        }
      }
    },
    skip: Platform.environment['CI'] == 'true',
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

Future<void> _capture(
  WidgetTester tester, {
  required FoldGeometry geometry,
  required String surface,
  required Widget home,
  double keyboardInset = 0,
  Duration settleFor = const Duration(milliseconds: 220),
  Future<void> Function()? afterPump,
}) async {
  // ignore: avoid_print
  print('CAPTURE ${geometry.suffix} $surface begin');
  await _allowOverflowEvidence(() async {
    await tester.pumpWidget(
      foldCaptureApp(
        geometry: geometry,
        keyboardInset: keyboardInset,
        home: home,
      ),
    );
    await tester.pump(settleFor);
    await afterPump?.call();
  });

  final evidence = await writeFoldPng(
    tester,
    surface: surface,
    geometry: geometry,
  );
  expect(
    evidence.file.existsSync() && evidence.file.lengthSync() > 0,
    isTrue,
    reason: 'PNG must be written for $surface ${geometry.suffix}',
  );
  expect(
    evidence.variance,
    greaterThan(1),
    reason: 'render must be non-blank for $surface ${geometry.suffix}',
  );
}

Future<void> _captureQuickActions(
  WidgetTester tester,
  FoldMatrixFixture fixture,
  FoldGeometry geometry,
) async {
  await _allowOverflowEvidence(() async {
    await tester.pumpWidget(
      foldCaptureApp(geometry: geometry, home: fixture.chatSurface()),
    );
    await tester.pump(const Duration(milliseconds: 180));
    final context = tester.element(find.byType(ChatPage));
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.bg,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      isScrollControlled: true,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ChangeNotifierProvider<QuickActionsViewModel>(
        create: (_) => buildFoldQuickActionsViewModel(),
        child: QuickActionsSheetBody(
          messenger: messenger,
          onSessionReset: fixture.chat.clearActiveSession,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 360));
  });
  final evidence = await writeFoldPng(
    tester,
    surface: 'chat-quick-actions',
    geometry: geometry,
  );
  expect(evidence.file.existsSync() && evidence.file.lengthSync() > 0, isTrue);
  expect(evidence.variance, greaterThan(1));
}

Future<void> _captureAttachSheet(
  WidgetTester tester,
  FoldMatrixFixture fixture,
  FoldGeometry geometry,
) async {
  await _allowOverflowEvidence(() async {
    await tester.pumpWidget(
      foldCaptureApp(geometry: geometry, home: fixture.chatSurface()),
    );
    await tester.pump(const Duration(milliseconds: 180));
    final context = tester.element(find.byType(ChatPage));
    showAttachSheet(context);
    await tester.pump(const Duration(milliseconds: 360));
  });
  final evidence = await writeFoldPng(
    tester,
    surface: 'chat-attach',
    geometry: geometry,
  );
  expect(evidence.file.existsSync() && evidence.file.lengthSync() > 0, isTrue);
  expect(evidence.variance, greaterThan(1));
}

Future<void> _capturePasteSheet(
  WidgetTester tester,
  FoldMatrixFixture fixture,
  FoldGeometry geometry,
) async {
  fixture.onboarding.show(OnboardingStep.pair);
  await _allowOverflowEvidence(() async {
    await tester.pumpWidget(
      foldCaptureApp(
        geometry: geometry,
        keyboardInset: 280,
        home: fixture.providers(child: const OnboardingPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 360));
    final context = tester.element(find.byType(OnboardingPage));
    showPasteQrSheet(context, onSubmit: (_) {});
    await tester.pump(const Duration(milliseconds: 360));
    await tester.enterText(find.byType(TextField).last, _typedPairingUri);
    await tester.pump(const Duration(milliseconds: 120));
  });
  final evidence = await writeFoldPng(
    tester,
    surface: 'pair-paste-qr',
    geometry: geometry,
  );
  expect(evidence.file.existsSync() && evidence.file.lengthSync() > 0, isTrue);
  expect(evidence.variance, greaterThan(1));
}

Future<void> _allowOverflowEvidence(Future<void> Function() body) async {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed by')) return;
    original?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
}

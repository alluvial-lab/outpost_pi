import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import 'fold_matrix_capture.dart';
import 'fold_matrix_fixtures.dart';

const _typedPairingUri =
    'outpostpi://pair?t=AAAAAAAAAAAAAAAAAAAAAA&'
    'epk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&'
    'rm=outpost-app&n=Studio%20MacBook%20Pro';

void main() {
  late Directory hiveDirectory;
  late MobileScannerPlatform originalScannerPlatform;
  http.Client? originalFontClient;
  late MockClient fixtureFontClient;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    await loadFoldGoldenFonts();
    final fontCacheDirectory = Directory(
      '${Directory.current.path}/.dart_tool/fold_matrix_fonts',
    )..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (_) async {
          return fontCacheDirectory.path;
        });
    originalFontClient = GoogleFonts.config.httpClient;
    fixtureFontClient = MockClient((request) async {
      final hash = request.url.pathSegments.last.replaceFirst('.ttf', '');
      final filename = switch (hash) {
        'd9e28ce88420fcbccb074f652afc16c1d496f7aca31311964c6a30bbdd71e4a0' =>
          'SpaceMono-Regular.ttf',
        '9bc9f9da68e4f847e99faab84b9202aa74430a0955675dcf949b79a65257c368' =>
          'SpaceMono-Bold.ttf',
        _ => throw StateError('Unexpected golden font request: $request'),
      };
      final bytes = File('test/fixtures/fonts/$filename').readAsBytesSync();
      return http.Response.bytes(bytes, 200);
    });
    GoogleFonts.config.httpClient = fixtureFontClient;
    await GoogleFonts.pendingFonts(<TextStyle>[
      GoogleFonts.spaceMono(),
      GoogleFonts.spaceMono(fontWeight: FontWeight.w700),
    ]);
    originalScannerPlatform = MobileScannerPlatform.instance;
    MobileScannerPlatform.instance = FoldCameraPlatform();

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
    MobileScannerPlatform.instance = originalScannerPlatform;
    await GoogleFonts.pendingFonts();
    GoogleFonts.config.httpClient = originalFontClient;
    fixtureFontClient.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
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
        final fixture = await tester.runAsync<FoldMatrixFixture>(
          FoldMatrixFixture.create,
        );
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
            afterPump: () async {
              if (geometry.width == 411 && geometry.height == 797) {
                _expectSpaceMonoMaterialRoles(tester);
              }
              if (geometry.width < 280) {
                expect(
                  find.byKey(const Key('home-header-compact')),
                  findsOneWidget,
                );
                expect(
                  find.byKey(const Key('home-filter-compact')),
                  findsOneWidget,
                );
                final relayStatus = tester.widget<Text>(
                  find.byKey(const Key('home-relay-status-label')),
                );
                expect(relayStatus.style?.fontSize, greaterThanOrEqualTo(12));
              }
              if (geometry.width == 797) {
                final listContent = find.byKey(const Key('home-list-content'));
                expect(listContent, findsWidgets);
                for (final element in listContent.evaluate()) {
                  expect(
                    tester
                        .getSize(find.byElementPredicate((e) => e == element))
                        .width,
                    lessThanOrEqualTo(560),
                  );
                }
              }
            },
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
            surface: 'two-pane-detail-placeholder',
            home: fixture.shellSurface(detailSelected: false),
          );
          await _capture(
            tester,
            geometry: geometry,
            surface: 'two-pane-keyboard',
            keyboardInset: 280,
            home: fixture.shellSurface(),
            afterPump: () async {
              final field = find.byType(TextField);
              if (field.evaluate().isNotEmpty) {
                await tester.tap(field.first, warnIfMissed: false);
                await tester.pump(const Duration(milliseconds: 120));
              }
            },
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
          await _capture(
            tester,
            geometry: geometry,
            surface: 'pairing-scanning',
            home: fixture.pairingScanningSurface(),
            settleFor: const Duration(milliseconds: 360),
            afterPump: () async {
              expect(
                find.byKey(const Key('fold-camera-placeholder')),
                findsOneWidget,
              );
            },
          );
          await _capturePasteSheet(tester, fixture, geometry);
          await _capture(
            tester,
            geometry: geometry,
            surface: 'sync-required',
            home: fixture.syncRequiredSurface(),
          );
          final safeAreaInsets = _realisticSafeAreaInsets(geometry);
          await _capture(
            tester,
            geometry: geometry,
            surface: 'storage-recovery-dark',
            safeAreaInsets: safeAreaInsets,
            home: fixture.storageRecoverySurface(),
          );
          await _capture(
            tester,
            geometry: geometry,
            surface: 'storage-recovery-light',
            brightness: Brightness.light,
            safeAreaInsets: safeAreaInsets,
            home: fixture.storageRecoverySurface(),
          );
          await _capture(
            tester,
            geometry: geometry,
            surface: 'home-no-peer',
            home: fixture.noPeerSurface(),
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

  testWidgets(
    'decoded PNG variance rejects a uniform image and accepts a real golden',
    (tester) async {
      final uniformPng = await tester.runAsync(_createUniformPng);
      expect(uniformPng, isNotNull);
      final uniformVariance = await tester.runAsync(
        () => samplePngVariance(uniformPng!),
      );
      expect(uniformVariance, closeTo(0, 0.0001));

      final realGolden = File('${foldGoldenDirectory().path}/home-411x797.png');
      expect(realGolden.existsSync(), isTrue);
      final realVariance = await tester.runAsync(
        () => samplePngVariance(realGolden.readAsBytesSync()),
      );
      expect(realVariance, isNotNull);
      expect(realVariance!, greaterThan(1));
    },
    skip: Platform.environment['CI'] == 'true',
  );
}

Future<Uint8List> _createUniformPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFF000000), ui.BlendMode.src);
  final image = await recorder.endRecording().toImage(8, 8);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not encode uniform PNG');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

void _expectSpaceMonoMaterialRoles(WidgetTester tester) {
  final theme = Theme.of(
    tester.element(find.byKey(const Key('home-header-standard'))),
  );
  for (final style in <TextStyle?>[
    theme.textTheme.displayLarge,
    theme.textTheme.headlineMedium,
    theme.textTheme.titleSmall,
    theme.textTheme.bodyLarge,
    theme.textTheme.labelLarge,
    theme.textButtonTheme.style?.textStyle?.resolve(<WidgetState>{}),
    theme.elevatedButtonTheme.style?.textStyle?.resolve(<WidgetState>{}),
    theme.outlinedButtonTheme.style?.textStyle?.resolve(<WidgetState>{}),
    theme.filledButtonTheme.style?.textStyle?.resolve(<WidgetState>{}),
  ]) {
    expect(style?.fontFamily, kMonoFamily);
  }
}

Future<void> _capture(
  WidgetTester tester, {
  required FoldGeometry geometry,
  required String surface,
  required Widget home,
  double keyboardInset = 0,
  Brightness brightness = Brightness.dark,
  EdgeInsets safeAreaInsets = EdgeInsets.zero,
  Duration settleFor = const Duration(milliseconds: 220),
  Future<void> Function()? afterPump,
}) async {
  // ignore: avoid_print
  print('CAPTURE ${geometry.suffix} $surface begin');
  await _pumpWithOverflowPolicy(
    geometry: geometry,
    surface: surface,
    body: () async {
      await tester.pumpWidget(
        foldCaptureApp(
          geometry: geometry,
          captureId: '$surface-${geometry.suffix}',
          keyboardInset: keyboardInset,
          brightness: brightness,
          safeAreaInsets: safeAreaInsets,
          home: home,
        ),
      );
      await tester.pump();
      await tester.pump(settleFor);
      await afterPump?.call();
    },
  );

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
  await _pumpWithOverflowPolicy(
    geometry: geometry,
    surface: 'chat-quick-actions',
    body: () async {
      await tester.pumpWidget(
        foldCaptureApp(
          geometry: geometry,
          captureId: 'chat-quick-actions-${geometry.suffix}',
          home: fixture.chatSurface(),
        ),
      );
      await tester.pump();
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 360));
      expect(find.byType(QuickActionsSheetBody), findsOneWidget);
      expect(find.byKey(const Key('attach-camera')), findsNothing);
    },
  );
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
  await _pumpWithOverflowPolicy(
    geometry: geometry,
    surface: 'chat-attach',
    body: () async {
      await tester.pumpWidget(
        foldCaptureApp(
          geometry: geometry,
          captureId: 'chat-attach-${geometry.suffix}',
          home: fixture.chatSurface(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      final context = tester.element(find.byType(ChatPage));
      showAttachSheet(context);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 360));
      expect(find.byKey(const Key('attach-camera')), findsOneWidget);
      expect(find.byType(QuickActionsSheetBody), findsNothing);
    },
  );
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
  await _pumpWithOverflowPolicy(
    geometry: geometry,
    surface: 'pair-paste-qr',
    body: () async {
      await tester.pumpWidget(
        foldCaptureApp(
          geometry: geometry,
          captureId: 'pair-paste-qr-${geometry.suffix}',
          keyboardInset: 280,
          home: fixture.providers(child: const OnboardingPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 360));
      final context = tester.element(find.byType(OnboardingPage));
      showPasteQrSheet(context, onSubmit: (_) {});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 360));
      await tester.enterText(find.byType(TextField).last, _typedPairingUri);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('Paste pairing code'), findsOneWidget);
      expect(find.byKey(const Key('attach-camera')), findsNothing);
    },
  );
  final evidence = await writeFoldPng(
    tester,
    surface: 'pair-paste-qr',
    geometry: geometry,
  );
  expect(evidence.file.existsSync() && evidence.file.lengthSync() > 0, isTrue);
  expect(evidence.variance, greaterThan(1));
}

Future<void> _pumpWithOverflowPolicy({
  required FoldGeometry geometry,
  required String surface,
  required Future<void> Function() body,
}) async {
  final overflows = <FlutterErrorDetails>[];
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed by')) {
      overflows.add(details);
      return;
    }
    original?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }

  if (overflows.isNotEmpty) {
    fail(
      'Overflow in $surface at ${geometry.suffix}: '
      '${overflows.first.exceptionAsString()}',
    );
  }
}

EdgeInsets _realisticSafeAreaInsets(FoldGeometry geometry) {
  if (geometry.width > geometry.height) {
    return const EdgeInsets.fromLTRB(24, 0, 24, 16);
  }
  return const EdgeInsets.fromLTRB(0, 24, 0, 24);
}

final class FoldCameraPlatform extends MobileScannerPlatform {
  final StreamController<BarcodeCapture?> _barcodes =
      StreamController<BarcodeCapture?>.broadcast();

  @override
  Stream<BarcodeCapture?> get barcodesStream => _barcodes.stream;

  @override
  Stream<TorchState> get torchStateStream =>
      Stream<TorchState>.value(TorchState.unavailable);

  @override
  Stream<double> get zoomScaleStateStream => Stream<double>.value(1);

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async {
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(411, 797),
      numberOfCameras: 1,
    );
  }

  @override
  Widget buildCameraView() {
    return const ColoredBox(
      key: Key('fold-camera-placeholder'),
      color: Color(0xFF182019),
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

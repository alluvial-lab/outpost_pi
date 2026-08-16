@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/data/preferences/preferences.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/pairing/owner_identity_bridge.dart';
import 'package:app/pairing/qr_scanner.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/onboarding/widgets/pair_step.dart';
import 'package:app/ui/pairing/pairing_page.dart';
import 'package:app/ui/pairing/states/pairing_state.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:outpost_pi_identity/outpost_pi_identity.dart';
import 'package:provider/provider.dart';
import 'package:qr/qr.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'PairingPage scans a real QR through mobile_scanner exactly once',
    (tester) async {
      final vm = _ScannerPairingViewModel();
      var pairedTransitions = 0;
      vm.addListener(() {
        if (vm.state is PairingPaired) pairedTransitions++;
      });

      await _exerciseScanner(
        tester,
        vm: vm,
        child: const PairingPage(),
        afterDetect: () async {
          expect(vm.scanCalls, 1);
          expect(pairedTransitions, 1);
        },
      );

      vm.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'PairStep scans a real QR through mobile_scanner exactly once',
    (tester) async {
      final vm = _ScannerPairingViewModel();
      var onPairedCalls = 0;

      await _exerciseScanner(
        tester,
        vm: vm,
        child: SizedBox(
          height: 800,
          child: PairStep(
            onPaired: () => onPairedCalls++,
            onBack: () {},
            onSkip: () {},
          ),
        ),
        afterDetect: () async {
          expect(vm.scanCalls, 1);
          expect(onPairedCalls, 1);
        },
      );

      vm.dispose();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// Exercise the production scanner widget and its native image-decoder path.
///
/// The test obtains a [BarcodeCapture] from the real platform implementation
/// via [MobileScannerController.analyzeImage], then routes that capture
/// through the production widget callback. This keeps the scanner boundary
/// native without requiring a device camera to be aimed at a second screen.
Future<void> _exerciseScanner(
  WidgetTester tester, {
  required _ScannerPairingViewModel vm,
  required Widget child,
  required Future<void> Function() afterDetect,
}) async {
  final qrContent = _buildPairingQrContent();
  final qrFile = await _writeQrPng(qrContent);
  MobileScannerController? controller;

  try {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: ChangeNotifierProvider.value(value: vm, child: child),
      ),
    );

    final scanner = await _findStartedScanner(tester);
    final scannerController = scanner.controller;
    if (scannerController == null) {
      throw TestFailure('MobileScanner did not expose its controller');
    }
    controller = scannerController;
    expect(scannerController.value.isRunning, isTrue);

    final capture = await scannerController.analyzeImage(
      qrFile.path,
      formats: const [BarcodeFormat.qrCode],
    );
    expect(capture, isNotNull);
    expect(capture!.barcodes, hasLength(1));
    expect(capture.barcodes.single.rawValue, qrContent);

    // Empty detections protect the null/empty guard before the first real QR.
    scanner.onDetect!(const BarcodeCapture());
    expect(vm.scanCalls, 0);

    // The native decode is delivered once, then delivered again to model the
    // duplicate camera frame that the one-shot scanner latch must suppress.
    scanner.onDetect!(capture);
    expect(scannerController.value.isRunning, isFalse);
    scanner.onDetect!(capture);
    expect(vm.scanCalls, 1);

    await tester.pump();
    await afterDetect();
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // PairingPage and PairStep both own the external controller and dispose it
    // in their State.dispose methods. A disposed controller must reject reuse.
    final disposedController = controller;
    if (disposedController != null) {
      await expectLater(
        disposedController.start(),
        throwsA(isA<MobileScannerException>()),
      );
    }
    await qrFile.delete();
  }
}

Future<MobileScanner> _findStartedScanner(WidgetTester tester) async {
  for (var attempt = 0; attempt < 120; attempt++) {
    final finder = find.byType(MobileScanner);
    if (finder.evaluate().isNotEmpty) {
      final scanner = tester.widget<MobileScanner>(finder);
      final controller = scanner.controller;
      if (controller != null && controller.value.isRunning) return scanner;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw TestFailure('MobileScanner did not start within 12 seconds');
}

/// Build the same URI shape emitted by the canonical pairing producer.
/// [QrPairPayload.tryParse] is the app-side boundary validator used as an
/// additional assertion that this test content is valid for the app.
String _buildPairingQrContent() {
  final token = base64Url
      .encode(List<int>.filled(16, 0x11))
      .replaceAll('=', '');
  final epk = base64Url.encode(List<int>.filled(32, 0x22)).replaceAll('=', '');
  final content = Uri(
    scheme: 'outpostpi',
    host: 'pair',
    queryParameters: <String, String>{
      't': token,
      'epk': epk,
      'n': 'boundary smoke',
      'rm': 'boundary-room',
    },
  ).toString();
  expect(QrPairPayload.tryParse(content), isNotNull);
  return content;
}

Future<File> _writeQrPng(String content) async {
  final qrCode = QrCode.fromData(
    data: content,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  );
  final qrImage = QrImage(qrCode);
  const quietZone = 4;
  const modulePixels = 10;
  final imageSize = (qrImage.moduleCount + quietZone * 2) * modulePixels;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final background = Paint()..color = Colors.white;
  final foreground = Paint()..color = Colors.black;
  canvas.drawRect(
    Rect.fromLTWH(0, 0, imageSize.toDouble(), imageSize.toDouble()),
    background,
  );
  for (var row = 0; row < qrImage.moduleCount; row++) {
    for (var column = 0; column < qrImage.moduleCount; column++) {
      if (!qrImage.isDark(row, column)) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          (column + quietZone) * modulePixels.toDouble(),
          (row + quietZone) * modulePixels.toDouble(),
          modulePixels.toDouble(),
          modulePixels.toDouble(),
        ),
        foreground,
      );
    }
  }
  final image = await recorder.endRecording().toImage(imageSize, imageSize);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  if (png == null) throw StateError('QR rasterization returned no PNG bytes');

  final file = File(
    '${Directory.systemTemp.path}/outpost_pi_boundary_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
  return file;
}

final class _ScannerPairingViewModel extends PairingViewModel {
  _ScannerPairingViewModel()
    : super(
        _NoopPairingStorage(),
        (qr, key) async => throw StateError('transport is not under test'),
        ConnectionManager(
          factory: (_, _) async =>
              throw StateError('connection is not under test'),
          storage: _NoopPairingStorage(),
        ),
        Preferences(FlutterSecureStorage()),
        OwnerIdentityBridge(
          InMemoryOwnerIdentityStore(),
          _NoopPairingStorage(),
        ),
      );

  int scanCalls = 0;

  @override
  Future<void> onQrScanned(String rawUri) async {
    scanCalls++;
    final qr = QrPairPayload.tryParse(rawUri);
    if (qr == null) throw StateError('native scanner returned invalid QR');
    emit(
      PairingPaired(
        peer: PeerRecord(
          remoteEpk: qr.epk,
          sessionName: qr.sessionName,
          relayUrl: 'ws://boundary.invalid',
          pairedAt: DateTime.now().toUtc().toIso8601String(),
          roomId: qr.roomId,
        ),
      ),
    );
  }
}

final class _NoopPairingStorage extends PairingStorage {
  _NoopPairingStorage() : super(FlutterSecureStorage());
}

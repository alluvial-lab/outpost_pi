import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const double foldDevicePixelRatio = 2.625;
const Key foldCaptureBoundaryKey = Key('fold-capture-boundary');

final class FoldGeometry {
  const FoldGeometry(this.width, this.height, {this.textScale = 1.0});

  final int width;
  final int height;
  final double textScale;

  Size get size => Size(width.toDouble(), height.toDouble());

  String get suffix =>
      '$width'
      'x$height'
      '${textScale == 1.0 ? '' : '-fs1.3'}';
}

const foldGeometries = <FoldGeometry>[
  FoldGeometry(411, 797),
  FoldGeometry(797, 411),
  FoldGeometry(701, 842),
  FoldGeometry(842, 701),
  FoldGeometry(350, 842),
  FoldGeometry(467, 842),
  FoldGeometry(234, 842),
  FoldGeometry(701, 842, textScale: 1.3),
  FoldGeometry(350, 842, textScale: 1.3),
];

Directory _repositoryRoot() {
  final current = Directory.current;
  return current.path.endsWith('${Platform.pathSeparator}app')
      ? current.parent
      : current;
}

Directory foldGoldenDirectory() => Directory(
  '${_repositoryRoot().path}/.work/session-notes/fold-pass-20260823/goldens',
);

/// Load the exact Space Mono faces used by production before any capture.
///
/// Goldens must never depend on google_fonts runtime fetching. A missing or
/// invalid fixture fails setup rather than silently falling back to Flutter's
/// rectangular test font.
Future<void> loadFoldGoldenFonts() async {
  const fixtures = <(String, String)>[
    ('SpaceMono_regular', 'SpaceMono-Regular.ttf'),
    ('SpaceMono_700', 'SpaceMono-Bold.ttf'),
  ];
  for (final (family, filename) in fixtures) {
    final file = File(
      '${_repositoryRoot().path}/app/test/fixtures/fonts/$filename',
    );
    if (!file.existsSync() || file.lengthSync() == 0) {
      throw StateError('Missing golden font fixture: ${file.path}');
    }
    final bytes = file.readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    try {
      await loader.load();
    } on Object catch (error) {
      throw StateError('Could not load golden font family $family: $error');
    }
  }
}

Widget foldCaptureApp({
  required FoldGeometry geometry,
  required String captureId,
  required Widget home,
  double keyboardInset = 0,
  Brightness brightness = Brightness.dark,
  EdgeInsets safeAreaInsets = EdgeInsets.zero,
}) {
  final keyboardVisible = keyboardInset > 0;
  return RepaintBoundary(
    key: foldCaptureBoundaryKey,
    child: MaterialApp(
      key: ValueKey<String>('fold-capture-app-$captureId'),
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.dark
          ? buildDarkTheme()
          : buildLightTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: geometry.size,
          devicePixelRatio: foldDevicePixelRatio,
          textScaler: TextScaler.linear(geometry.textScale),
          platformBrightness: brightness,
          padding: safeAreaInsets.copyWith(
            bottom: keyboardVisible ? 0 : safeAreaInsets.bottom,
          ),
          viewPadding: safeAreaInsets,
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: home,
      ),
    ),
  );
}

Future<void> configureFoldView(
  WidgetTester tester,
  FoldGeometry geometry,
) async {
  tester.view.devicePixelRatio = foldDevicePixelRatio;
  tester.view.physicalSize = Size(
    geometry.width * foldDevicePixelRatio,
    geometry.height * foldDevicePixelRatio,
  );
  await tester.pump();
}

Future<({File file, double variance})> writeFoldPng(
  WidgetTester tester, {
  required String surface,
  required FoldGeometry geometry,
}) async {
  final directory = foldGoldenDirectory()..createSync(recursive: true);
  final file = File('${directory.path}/$surface-${geometry.suffix}.png');
  goldenFileComparator = FoldSavingComparator(file);

  // matchesGoldenFile rasterizes through the test binding's own pipeline
  // (manual RepaintBoundary.toImage deadlocks under the fake clock in this
  // environment). A saving comparator turns the golden comparison into a
  // file write: the assert always passes, evidence lands on disk.
  await expectLater(
    find.byKey(foldCaptureBoundaryKey),
    matchesGoldenFile('fold-saved/$surface-${geometry.suffix}.png'),
  );
  if (!file.existsSync() || file.lengthSync() == 0) {
    throw StateError('golden save failed for $surface at ${geometry.suffix}');
  }
  final bytes = file.readAsBytesSync();
  final variance = await tester.runAsync(() => samplePngVariance(bytes));
  if (variance == null) {
    throw StateError('golden variance decode failed for ${file.path}');
  }
  return (file: file, variance: variance);
}

class FoldSavingComparator extends GoldenFileComparator {
  FoldSavingComparator(this.target);

  final File target;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    target.writeAsBytesSync(imageBytes, flush: true);
    return true;
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) async {
    target.writeAsBytesSync(imageBytes, flush: true);
  }

  @override
  Uri getTestUri(Uri key, int? version) => key;
}

/// Decode a PNG and sample luminance variance from its RGBA pixels.
Future<double> samplePngVariance(Uint8List pngBytes) async {
  final codec = await ui.instantiateImageCodec(pngBytes);
  try {
    final frame = await codec.getNextFrame();
    try {
      final rgba = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rgba == null) throw StateError('PNG did not decode to RGBA pixels');
      return _sampleRgbaVariance(
        rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      );
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

double _sampleRgbaVariance(List<int> rgba) {
  if (rgba.length < 4) return 0;
  final pixels = rgba.length ~/ 4;
  final stride = math.max(1, pixels ~/ 4096);
  var count = 0;
  var sum = 0.0;
  var sumSquares = 0.0;
  for (var pixel = 0; pixel < pixels; pixel += stride) {
    final offset = pixel * 4;
    final luminance =
        rgba[offset] * 0.2126 +
        rgba[offset + 1] * 0.7152 +
        rgba[offset + 2] * 0.0722;
    count++;
    sum += luminance;
    sumSquares += luminance * luminance;
  }
  final mean = sum / count;
  return sumSquares / count - mean * mean;
}

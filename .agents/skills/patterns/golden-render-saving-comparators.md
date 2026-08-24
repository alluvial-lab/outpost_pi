# Pattern: Golden Render Saving Comparators

## Rationale

Flutter render evidence must use the test binding's golden pipeline, even when the goal is capture rather than pass/fail comparison. Install a comparator that writes the raster to an explicit evidence path, invoke `matchesGoldenFile`, then validate that the file exists and contains non-blank pixels. This avoids the fake-clock deadlock of manual `RepaintBoundary.toImage` while keeping every captured surface on one deterministic path.

## When to use

Use for render matrices or visual smoke evidence where each surface/geometry pair must produce a durable PNG:

- configure the test binding and fixture fonts before capture;
- capture through `matchesGoldenFile` with a saving comparator;
- fail on missing/empty output and a decoded blank render;
- keep capture orchestration separate from the surface-specific setup.

## When not to use

Do not use a saving comparator to hide a real golden mismatch in a correctness test. For ordinary visual regression tests, use the normal comparator and committed goldens. Do not call `toImage` directly when the test environment's fake clock can deadlock the raster pipeline.

## Examples

### Example 1: Route the golden assertion into a saving comparator

**File:** `app/test/golden/fold_matrix_capture.dart:127-151`

```dart
final file = File('${directory.path}/$surface-${geometry.suffix}.png');
goldenFileComparator = FoldSavingComparator(file);

await expectLater(
  find.byKey(foldCaptureBoundaryKey),
  matchesGoldenFile('fold-saved/$surface-${geometry.suffix}.png'),
);
if (!file.existsSync() || file.lengthSync() == 0) {
  throw StateError('golden save failed for $surface at ${geometry.suffix}');
}
final bytes = file.readAsBytesSync();
final variance = await tester.runAsync(() => samplePngVariance(bytes));
if (variance == null) throw StateError('golden variance decode failed');
```

### Example 2: Reuse the capture contract for ordinary surfaces

**File:** `app/test/golden/fold_matrix_test.dart:327-364`

```dart
await _pumpWithOverflowPolicy(
  geometry: geometry,
  surface: surface,
  body: () async {
    await tester.pumpWidget(foldCaptureApp(
      geometry: geometry,
      captureId: '$surface-${geometry.suffix}',
      home: home,
    ));
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
expect(evidence.file.lengthSync(), greaterThan(0));
expect(evidence.variance, greaterThan(1));
```

### Example 3: Capture a modal surface through the same writer

**File:** `app/test/golden/fold_matrix_test.dart:377-426`

```dart
await _pumpWithOverflowPolicy(
  geometry: geometry,
  surface: 'chat-quick-actions',
  body: () async {
    await tester.pumpWidget(foldCaptureApp(
      geometry: geometry,
      captureId: 'chat-quick-actions-${geometry.suffix}',
      home: fixture.chatSurface(),
    ));
    // Open and settle the modal, then assert its semantic state.
  },
);
final evidence = await writeFoldPng(
  tester,
  surface: 'chat-quick-actions',
  geometry: geometry,
);
expect(evidence.file.existsSync() && evidence.file.lengthSync() > 0, isTrue);
expect(evidence.variance, greaterThan(1));
```

### Example 4: Capture another modal without bypassing the pipeline

**File:** `app/test/golden/fold_matrix_test.dart:429-463`

```dart
await _pumpWithOverflowPolicy(
  geometry: geometry,
  surface: 'chat-attach',
  body: () async {
    await tester.pumpWidget(foldCaptureApp(
      geometry: geometry,
      captureId: 'chat-attach-${geometry.suffix}',
      home: fixture.chatSurface(),
    ));
    showAttachSheet(tester.element(find.byType(ChatPage)));
    await tester.pump(const Duration(milliseconds: 360));
  },
);
final evidence = await writeFoldPng(
  tester,
  surface: 'chat-attach',
  geometry: geometry,
);
expect(evidence.variance, greaterThan(1));
```

## Common violations

- Calling `RepaintBoundary.toImage` directly in this fake-clock harness.
- Installing a comparator but never checking that a file was actually written.
- Treating a uniform or decode-failed PNG as valid evidence.
- Reimplementing capture logic in each surface instead of routing all surfaces through `writeFoldPng`.

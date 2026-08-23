import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/storage_recovery/transcript_storage_recovery_page.dart';
import 'package:app/ui/sync_required/sync_required_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void configureView(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
  }

  void expectExplicitTextFloor(WidgetTester tester, Finder scope) {
    for (final text
        in find.descendant(of: scope, matching: find.byType(Text)).evaluate()) {
      final widget = text.widget as Text;
      final fontSize = widget.style?.fontSize;
      if (fontSize != null) {
        expect(
          fontSize,
          greaterThanOrEqualTo(12),
          reason: '"${widget.data}" uses $fontSize sp',
        );
      }
    }
  }

  testWidgets('system pages cap and center content on the unfolded display', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    configureView(tester, const Size(842, 701));

    await tester.pumpWidget(
      MaterialApp(theme: buildDarkTheme(), home: const SyncRequiredPage()),
    );
    await tester.pump();
    final syncContent = find.byKey(
      const Key('sync-required-responsive-content'),
    );
    final syncRect = tester.getRect(syncContent);
    expect(syncRect.width, lessThanOrEqualTo(460));
    expect(syncRect.center.dx, closeTo(421, 0.5));
    expectExplicitTextFloor(tester, syncContent);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: TranscriptStorageRecoveryPage(
          onRetry: () async {},
          onDiscard: () async {},
        ),
      ),
    );
    await tester.pump();
    final recoveryContent = find.byKey(
      const Key('storage-recovery-responsive-content'),
    );
    final recoveryRect = tester.getRect(recoveryContent);
    expect(recoveryRect.width, lessThanOrEqualTo(460));
    expect(recoveryRect.center.dx, closeTo(421, 0.5));
    expect(recoveryRect.center.dy, closeTo(350.5, 1));
    expectExplicitTextFloor(tester, recoveryContent);
  });

  testWidgets('storage recovery remains scrollable in fold landscape', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    configureView(tester, const Size(797, 411));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: TranscriptStorageRecoveryPage(
          onRetry: () async {},
          onDiscard: () async {},
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('storage-recovery-scroll-view')),
      findsOneWidget,
    );
    final content = find.byKey(
      const Key('storage-recovery-responsive-content'),
    );
    final rect = tester.getRect(content);
    expect(rect.width, lessThanOrEqualTo(460));
    expect(rect.center.dx, closeTo(797 / 2, 0.5));
    expect(tester.takeException(), isNull);
  });
}

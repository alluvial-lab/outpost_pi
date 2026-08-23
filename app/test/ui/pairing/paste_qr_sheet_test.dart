import 'package:app/ui/pairing/widgets/paste_qr_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'landscape keyboard keeps paste QR sheet scrollable without overflow',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(797, 411);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);

      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      // ignore: unawaited_futures
      showPasteQrSheet(pageContext, onSubmit: (_) {});
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('paste-qr-adaptive-sheet')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('paste-qr-adaptive-sheet'))).width,
        560,
      );
      final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const Key('paste-qr-sheet-scroll')),
      );
      expect(
        scroll.padding,
        const EdgeInsets.only(bottom: 280),
        reason: 'the keyboard inset belongs to the bounded scroll content',
      );
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), 'outpostpi://pair?t=test');
      await tester.drag(
        find.byKey(const Key('paste-qr-sheet-scroll')),
        const Offset(0, -280),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pair').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

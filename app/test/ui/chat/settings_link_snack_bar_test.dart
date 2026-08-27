import 'package:app/ui/chat/widgets/settings_link_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('permission feedback opens the application settings link', (
    tester,
  ) async {
    var settingsLaunches = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  buildSettingsLinkSnackBar(
                    message: 'Permission is off.',
                    openSettings: () async {
                      settingsLaunches += 1;
                    },
                  ),
                );
              },
              child: const Text('Show permission feedback'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show permission feedback'));
    await tester.pumpAndSettle();
    expect(find.text('Permission is off.'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Settings'));
    await tester.pump();
    expect(settingsLaunches, 1);
  });
}

import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';
import 'package:app/ui/onboarding/widgets/relay_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renders a required self-hosted relay form without a community card',
    (tester) async {
      var submitCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: RelayStep(
              state: const OnboardingInProgress(step: OnboardingStep.relay),
              onCustomUrl: (_) {},
              onBack: () {},
              onNext: () => submitCount += 1,
            ),
          ),
        ),
      );

      expect(find.text('Configure your relay'), findsOneWidget);
      expect(find.text('Self-hosted relay URL'), findsOneWidget);
      expect(find.textContaining('Community relay'), findsNothing);
      expect(find.textContaining('default relay'), findsNothing);

      // Submit remains enabled so the ViewModel can render the shared empty-URL
      // validation error rather than silently disabling the only recovery path.
      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
      await tester.tap(continueButton);
      expect(submitCount, 1);
    },
  );
}

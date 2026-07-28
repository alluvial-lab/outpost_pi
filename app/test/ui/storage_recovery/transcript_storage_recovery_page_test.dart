import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/storage_recovery/transcript_storage_recovery_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('discard remains explicit through confirmation and cancel', (
    tester,
  ) async {
    var retries = 0;
    var discards = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: TranscriptStorageRecoveryPage(
          onRetry: () async => retries += 1,
          onDiscard: () async => discards += 1,
        ),
      ),
    );

    expect(find.text('Local transcripts unavailable'), findsOneWidget);
    expect(find.textContaining('may sync again'), findsOneWidget);
    expect(
      find.textContaining('older or local-only history may not return'),
      findsOneWidget,
    );
    expect(find.textContaining('audit.jsonl'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(discards, 0);

    await tester.tap(find.text('Discard local transcripts'));
    await tester.pumpAndSettle();
    expect(find.text('Discard and continue'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(discards, 0);

    await tester.tap(find.text('Discard local transcripts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard and continue'));
    await tester.pumpAndSettle();
    expect(discards, 1);
  });

  testWidgets('a discard failure stays blocking and does not expose details', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: TranscriptStorageRecoveryPage(
          onRetry: () async {},
          onDiscard: () async => throw StateError('/private/ciphertext'),
        ),
      ),
    );

    await tester.tap(find.text('Discard local transcripts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard and continue'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not discard local transcripts. Nothing else was reset.'),
      findsOneWidget,
    );
    expect(find.textContaining('/private/ciphertext'), findsNothing);
    expect(find.text('Discard local transcripts'), findsOneWidget);
  });
}

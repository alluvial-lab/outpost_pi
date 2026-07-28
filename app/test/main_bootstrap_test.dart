import 'package:app/data/local/transcript_storage_key.dart';
import 'package:app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('recoverable key loss blocks services until confirmed discard', (
    tester,
  ) async {
    var storageAttempts = 0;
    var dependencyStarts = 0;
    var discards = 0;
    var discarded = false;

    await tester.pumpWidget(
      OutpostPiBootstrap(
        initializeStorage: () async {
          storageAttempts += 1;
          if (!discarded) {
            throw const TranscriptStorageKeyException(
              'missing_provisioned_key',
            );
          }
        },
        discardUnreadableTranscripts: () async {
          discards += 1;
          discarded = true;
        },
        initializeDependencies: () async => dependencyStarts += 1,
        appBuilder: (_) => const MaterialApp(home: Text('ready app')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local transcripts unavailable'), findsOneWidget);
    expect(find.text('ready app'), findsNothing);
    expect(dependencyStarts, 0);
    expect(discards, 0);

    await tester.tap(find.text('Discard local transcripts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(discards, 0, reason: 'cancel cannot silently discard ciphertext');
    expect(dependencyStarts, 0);

    await tester.tap(find.text('Discard local transcripts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard and continue'));
    await tester.pumpAndSettle();

    expect(discards, 1);
    expect(storageAttempts, 2);
    expect(dependencyStarts, 1);
    expect(find.text('ready app'), findsOneWidget);
  });

  testWidgets('retry can recover without discarding local transcripts', (
    tester,
  ) async {
    var transientFailure = true;
    var discards = 0;
    var dependencyStarts = 0;

    await tester.pumpWidget(
      OutpostPiBootstrap(
        initializeStorage: () async {
          if (transientFailure) {
            throw const TranscriptStorageKeyException(
              'encrypted_box_unreadable',
            );
          }
        },
        discardUnreadableTranscripts: () async => discards += 1,
        initializeDependencies: () async => dependencyStarts += 1,
        appBuilder: (_) => const MaterialApp(home: Text('ready app')),
      ),
    );
    await tester.pumpAndSettle();

    transientFailure = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(discards, 0);
    expect(dependencyStarts, 1);
    expect(find.text('ready app'), findsOneWidget);
  });
}

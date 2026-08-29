import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/home/widgets/session_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _peer = PeerRecord(
  remoteEpk: 'epk',
  sessionName: 'Pi',
  relayUrl: 'ws://localhost',
  pairedAt: '2026-01-01T00:00:00Z',
);

Widget _tile({
  bool isLive = false,
  bool isReconnecting = false,
  bool isWorking = false,
  bool isOrchestrating = false,
}) => MaterialApp(
  theme: buildDarkTheme(),
  home: SessionTile(
    peer: _peer,
    room: const RoomInfo(roomId: 'main', startedAt: 1, background: true),
    isLive: isLive,
    isReconnecting: isReconnecting,
    isWorking: isWorking,
    isOrchestrating: isOrchestrating,
    onOpen: () {},
  ),
);

Color _dotColor(WidgetTester tester) {
  final dot = tester.widget<Container>(
    find.byKey(const Key('home-presence-dot')),
  );
  return (dot.decoration! as BoxDecoration).color!;
}

void main() {
  testWidgets('renders all five room status states', (tester) async {
    final colors = AppColors.dark;
    final pulse = find.byKey(const Key('home-presence-pulse'));

    await tester.pumpWidget(_tile());
    await tester.pump(const Duration(milliseconds: 500));
    expect(_dotColor(tester), colors.muted);
    expect(pulse, findsNothing);

    await tester.pumpWidget(_tile(isLive: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_dotColor(tester), colors.success);
    expect(pulse, findsNothing);

    await tester.pumpWidget(_tile(isReconnecting: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_dotColor(tester), colors.warning);
    expect(pulse, findsNothing);

    await tester.pumpWidget(_tile(isLive: true, isOrchestrating: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_dotColor(tester), colors.working);
    expect(pulse, findsOneWidget);

    await tester.pumpWidget(_tile(isLive: true, isWorking: true));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_dotColor(tester), colors.working);
    expect(pulse, findsNothing);
  });

  testWidgets('suppresses cached background state when the room is not live', (
    tester,
  ) async {
    await tester.pumpWidget(_tile(isOrchestrating: true));
    await tester.pump(const Duration(milliseconds: 500));

    expect(_dotColor(tester), AppColors.dark.muted);
    expect(find.byKey(const Key('home-presence-pulse')), findsNothing);
  });

  testWidgets(
    'working takes precedence over background and disposes its pulse',
    (tester) async {
      final pulse = find.byKey(const Key('home-presence-pulse'));
      await tester.pumpWidget(_tile(isLive: true, isOrchestrating: true));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(pulse, findsOneWidget);

      await tester.pumpWidget(
        _tile(isLive: true, isWorking: true, isOrchestrating: true),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(pulse, findsNothing);
      expect(_dotColor(tester), AppColors.dark.working);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

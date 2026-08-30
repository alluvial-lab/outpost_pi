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
  String? model = 'gpt-5',
}) => MaterialApp(
  theme: buildDarkTheme(),
  home: SessionTile(
    peer: _peer,
    room: RoomInfo(
      roomId: 'main',
      startedAt: 1,
      model: model,
      background: true,
    ),
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
  testWidgets('renders steady blue for turn and background work', (
    tester,
  ) async {
    final colors = AppColors.dark;

    await tester.pumpWidget(_tile(isLive: true, isOrchestrating: true));
    expect(_dotColor(tester), colors.working);
    expect(find.byKey(const Key('home-presence-pulse')), findsNothing);

    await tester.pumpWidget(
      _tile(isLive: true, isWorking: true, isOrchestrating: true),
    );
    expect(_dotColor(tester), colors.working);
    expect(find.byKey(const Key('home-presence-pulse')), findsNothing);

    await tester.pumpWidget(_tile());
    expect(_dotColor(tester), colors.muted);

    await tester.pumpWidget(_tile(isLive: true));
    expect(_dotColor(tester), colors.success);

    await tester.pumpWidget(_tile(isReconnecting: true));
    expect(_dotColor(tester), colors.warning);
  });

  testWidgets('background subtitle swaps and restores when work drains', (
    tester,
  ) async {
    await tester.pumpWidget(_tile(isLive: true));
    expect(find.text('gpt-5'), findsOneWidget);
    expect(find.text('background work'), findsNothing);

    await tester.pumpWidget(_tile(isLive: true, isOrchestrating: true));
    expect(find.text('background work'), findsOneWidget);
    expect(find.text('gpt-5'), findsNothing);

    await tester.pumpWidget(_tile(isLive: true));
    expect(find.text('gpt-5'), findsOneWidget);
    expect(find.text('background work'), findsNothing);
  });

  testWidgets('suppresses cached background state when the room is not live', (
    tester,
  ) async {
    await tester.pumpWidget(_tile(isOrchestrating: true));

    expect(_dotColor(tester), AppColors.dark.muted);
    expect(find.text('background work'), findsNothing);
  });

  testWidgets('background surface is safe to unmount', (tester) async {
    await tester.pumpWidget(_tile(isLive: true, isOrchestrating: true));
    expect(find.text('background work'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

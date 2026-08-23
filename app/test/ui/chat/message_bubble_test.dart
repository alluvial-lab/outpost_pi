// Agent output fills phone widths but keeps a readable centered measure on
// wide single-pane windows.

import 'package:app/domain/session_state.dart';
import 'package:app/ui/chat/widgets/agent_markdown.dart';
import 'package:app/ui/chat/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AssistantBubble caps wide prose at the reading measure', (
    tester,
  ) async {
    const longText =
        'This is a sufficiently long agent reply that would have wrapped at '
        'the old 340px cap but should now span the full content width of the '
        'message list so it reads naturally on wide screens.';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 797,
            child: AssistantBubble(AssistantMsg(id: 'a1', text: longText)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AgentMarkdown), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('assistant-reading-column'))).width,
      640,
      reason: 'wide prose should use the shared 640dp reading measure',
    );
  });

  testWidgets('delivery status text keeps the 12sp operational floor', (
    tester,
  ) async {
    for (final status in <UserMsgStatus>[
      UserMsgStatus.pending,
      UserMsgStatus.failed,
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserBubble(
              UserMsg(id: 'u1', text: 'message', status: status),
            ),
          ),
        ),
      );
      await tester.pump();
      final key = status == UserMsgStatus.pending
          ? const Key('message-delivery-sending')
          : const Key('message-delivery-failed');
      final text = tester.widget<Text>(find.byKey(key));
      expect(text.style?.fontSize, greaterThanOrEqualTo(12));
    }
  });

  testWidgets('AssistantBubble is selectable (copyable)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssistantBubble(AssistantMsg(id: 'a1', text: 'reply')),
        ),
      ),
    );
    await tester.pump();
    // AgentMarkdown wraps the reply in a SelectionArea when selectable.
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('UserBubble text is selectable (copyable)', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UserBubble(UserMsg(id: 'u1', text: 'my message')),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('my message'), findsOneWidget);
  });
}

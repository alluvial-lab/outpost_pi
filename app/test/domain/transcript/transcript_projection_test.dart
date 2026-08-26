import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
import 'package:app/protocol/protocol.dart' show UserMessageStreamingBehavior;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const session = 'sess-a';
  final base = DateTime.utc(2026, 1, 1);

  UserMessageSubmitted submitted(
    String id,
    String text, {
    String s = session,
  }) => UserMessageSubmitted(
    eventId: 'local:$id',
    sessionId: s,
    ts: base,
    clientMessageId: id,
    text: text,
  );

  UserMessageConfirmed confirmed(
    String id,
    String text, {
    String s = session,
  }) => UserMessageConfirmed(
    eventId: 'server:user:$id',
    sessionId: s,
    ts: base,
    clientMessageId: id,
    text: text,
  );

  UserMessageFailed failed(String id, String message, {String s = session}) =>
      UserMessageFailed(
        eventId: 'local:failed:$id',
        sessionId: s,
        ts: base,
        clientMessageId: id,
        code: 'send_timeout',
        message: message,
      );

  test('transport and turn axes compose without flattening', () {
    const transports = <ChatTransportProjection>[
      ChatTransportOnline(roomId: 'main'),
      ChatTransportRetrying(attempt: 2, nextRetry: Duration(seconds: 5)),
      ChatTransportOffline(reason: 'relay unavailable'),
    ];
    const turns = <AppTurnProjection>[
      AppTurnProjection(status: AppTurnStatus.idle),
      AppTurnProjection(
        status: AppTurnStatus.working,
        turnId: 'turn-1',
        replyTo: 'user-1',
      ),
      AppTurnProjection(
        status: AppTurnStatus.awaitingTool,
        turnId: 'turn-1',
        replyTo: 'user-1',
      ),
      AppTurnProjection(
        status: AppTurnStatus.streaming,
        turnId: 'turn-1',
        replyTo: 'user-1',
      ),
      AppTurnProjection(status: AppTurnStatus.error, error: 'provider failed'),
      AppTurnProjection.stale,
    ];

    for (final transport in transports) {
      for (final turn in turns) {
        final status = ChatStatusProjection(
          transport: transport,
          turn: turn,
          steering: const SteeringPending(
            clientMessageId: 'steer-1',
            text: 'refine this',
          ),
        );
        expect(status.transport, same(transport));
        expect(status.turn, same(turn));
        expect(status.steering, isA<SteeringPending>());
        expect(
          status.canCancel,
          transport is ChatTransportOnline && turn.working,
        );
      }
    }
  });

  test(
    'matching-session idle metadata clears stale transcript working after reconnect',
    () {
      final projection = deriveChatTurnProjection(
        room: const RoomTurnProjection(
          status: AppTurnStatus.idle,
          sessionId: session,
        ),
        transcript: const TranscriptTurnView(
          status: AppTurnStatus.working,
          sessionId: session,
          turnId: 'turn-old',
          replyTo: 'user-old',
        ),
        streaming: const StreamingMessage(
          inReplyTo: 'user-old',
          buffer: 'stale delta',
        ),
      );

      expect(projection, AppTurnProjection.idle);
      expect(projection.working, isFalse);
    },
  );

  test(
    'older-session idle metadata cannot clobber a live replacement turn',
    () {
      final projection = deriveChatTurnProjection(
        room: const RoomTurnProjection(
          status: AppTurnStatus.idle,
          sessionId: 'sess-old',
        ),
        transcript: const TranscriptTurnView(
          status: AppTurnStatus.working,
          sessionId: 'sess-current',
          turnId: 'turn-current',
          replyTo: 'user-current',
        ),
        streaming: const StreamingMessage(
          inReplyTo: 'user-current',
          buffer: 'live delta',
        ),
      );

      expect(projection.status, AppTurnStatus.streaming);
      expect(projection.working, isTrue);
      expect(projection.cancelTargetId, 'user-current');
    },
  );

  test('authoritative replay backfill renders by canonical server time', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [
        UserMessageConfirmed(
          eventId: 'server:user:cli_1',
          sessionId: session,
          ts: base,
          clientMessageId: 'cli_1',
          text: 'live prompt',
        ),
        AssistantMessageCommitted(
          eventId: 'server:assistant:msg_1',
          sessionId: session,
          ts: base.add(const Duration(milliseconds: 100)),
          messageId: 'msg_1',
          replyTo: 'cli_1',
          text: 'live response',
        ),
        UserMessageConfirmed(
          eventId: 'server:user:cli_2',
          sessionId: session,
          ts: base.add(const Duration(milliseconds: 50)),
          clientMessageId: 'cli_2',
          text: 'backfilled prompt',
        ),
        AssistantMessageCommitted(
          eventId: 'server:assistant:msg_2',
          sessionId: session,
          ts: base.add(const Duration(milliseconds: 60)),
          messageId: 'msg_2',
          replyTo: 'cli_2',
          text: 'backfilled response',
        ),
      ],
    );

    expect(projection.messages.map((message) => message.id), [
      'cli_1',
      'cli_2',
      'msg_2',
      'msg_1',
    ]);
  });

  test(
    'reconnect backfill preserves canonical order across incremental hydration',
    () {
      final liveEvents = <TranscriptEvent>[
        UserMessageConfirmed(
          eventId: 'server:user:live',
          sessionId: session,
          ts: base,
          clientMessageId: 'live-user',
          text: 'live prompt',
        ),
        AssistantMessageCommitted(
          eventId: 'server:assistant:live',
          sessionId: session,
          ts: base.add(const Duration(milliseconds: 100)),
          messageId: 'live-assistant',
          replyTo: 'live-user',
          text: 'live response',
        ),
      ];
      final replayEvents = <TranscriptEvent>[
        UserMessageConfirmed(
          eventId: 'server:user:backfill',
          sessionId: session,
          ts: base.add(const Duration(milliseconds: 50)),
          clientMessageId: 'backfill-user',
          text: 'backfilled prompt',
        ),
        AssistantMessageCommitted(
          eventId: 'server:assistant:backfill',
          sessionId: session,
          ts: base.add(const Duration(milliseconds: 60)),
          messageId: 'backfill-assistant',
          replyTo: 'backfill-user',
          text: 'backfilled response',
        ),
      ];
      final reducer = TranscriptProjectionReducer.empty(sessionId: session);

      final liveUpdate = reducer.applyAll(liveEvents);
      expect(liveUpdate.projection.messages.map((message) => message.id), [
        'live-user',
        'live-assistant',
      ]);

      final replayUpdate = reducer.applyAll(replayEvents);
      expect(replayUpdate.acceptedEvents, hasLength(replayEvents.length));
      expect(replayUpdate.firstChangedMessageIndex, 1);
      expect(replayUpdate.projection.messages.map((message) => message.id), [
        'live-user',
        'backfill-user',
        'backfill-assistant',
        'live-assistant',
      ]);

      final duplicateReplay = reducer.applyAll(replayEvents);
      expect(duplicateReplay.acceptedEvents, isEmpty);
      expect(duplicateReplay.firstChangedMessageIndex, isNull);
      expect(duplicateReplay.projection.messages.map((message) => message.id), [
        'live-user',
        'backfill-user',
        'backfill-assistant',
        'live-assistant',
      ]);

      final cleanProjection = deriveTranscriptProjection(
        sessionId: session,
        events: [...liveEvents, ...replayEvents],
      );
      _expectProjectionEquivalent(replayUpdate.projection, cleanProjection);
    },
  );

  test('server-timed tool ignores phone skew when result precedes request', () {
    final skewedPhoneNow = base.add(const Duration(hours: 12));
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [
        UserMessageSubmitted(
          eventId: 'local:phone-skew',
          sessionId: session,
          ts: skewedPhoneNow,
          clientMessageId: 'phone-local',
          text: 'optimistic local tail',
        ),
        AssistantMessageCommitted(
          eventId: 'server:assistant:before-tool',
          sessionId: session,
          ts: base.add(const Duration(milliseconds: 10)),
          messageId: 'before-tool',
          replyTo: 'cli_1',
          text: 'Starting the inspection.',
        ),
        AssistantMessageCommitted(
          eventId: 'server:assistant:after-tool',
          sessionId: session,
          ts: base.add(const Duration(milliseconds: 40)),
          messageId: 'after-tool',
          replyTo: 'cli_1',
          text: 'Inspection complete.',
        ),
        ToolFinished(
          eventId: 'server:tool:done:t1',
          sessionId: session,
          ts: base.add(const Duration(milliseconds: 50)),
          toolCallId: 't1',
          result: 'ok',
        ),
        ToolRequested(
          eventId: 'server:tool:req:t1',
          sessionId: session,
          ts: base.add(const Duration(milliseconds: 20)),
          toolCallId: 't1',
          tool: 'Bash',
          args: const {'command': 'pwd'},
        ),
      ],
    );

    expect(projection.messages.map((message) => message.id), [
      'before-tool',
      't1',
      'after-tool',
      'phone-local',
    ]);
  });

  test('local pending remains visible after authoritative replay prefix', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [submitted('cli_1', 'hello'), confirmed('server_old', 'older')],
    );

    expect(projection.messages, [
      const UserMsg(id: 'server_old', text: 'older'),
      const UserMsg(id: 'cli_1', text: 'hello', status: UserMsgStatus.pending),
    ]);
    expect(projection.turn.status, AppTurnStatus.working);
  });

  test(
    'steering acceptance stays pending until timestamped pickup anchors it',
    () {
      final early = <TranscriptEvent>[
        confirmed('primary', 'first prompt'),
        UserMessageSubmitted(
          eventId: 'local:steer-1',
          sessionId: session,
          ts: base.add(const Duration(milliseconds: 1)),
          clientMessageId: 'steer-1',
          text: 'refine this',
          awaitingPickup: true,
        ),
        UserMessageConfirmed(
          eventId: 'server:early:steer-1',
          sessionId: session,
          ts: base.add(const Duration(milliseconds: 2)),
          clientMessageId: 'steer-1',
          text: 'refine this',
          streamingBehavior: UserMessageStreamingBehavior.steer,
          semanticPickup: false,
        ),
        AssistantMessageCommitted(
          eventId: 'server:assistant:primary',
          sessionId: session,
          ts: base.add(const Duration(milliseconds: 3)),
          messageId: 'assistant-primary',
          replyTo: 'primary',
          text: 'first response',
        ),
      ];

      final accepted = deriveTranscriptProjection(
        sessionId: session,
        events: [...early, early[2]],
      );
      expect(accepted.messages.map((message) => message.id), [
        'primary',
        'assistant-primary',
      ]);
      expect(
        accepted.steering,
        const SteeringPending(clientMessageId: 'steer-1', text: 'refine this'),
      );

      final pickup = UserMessageConfirmed(
        eventId: 'server:pickup:steer-1',
        sessionId: session,
        ts: base.add(const Duration(milliseconds: 4)),
        clientMessageId: 'steer-1',
        text: 'refine this',
      );
      final pickedUp = deriveTranscriptProjection(
        sessionId: session,
        events: [...early, pickup, pickup],
      );
      expect(pickedUp.messages.map((message) => message.id), [
        'primary',
        'assistant-primary',
        'steer-1',
      ]);
      expect(pickedUp.steering, isA<NoSteering>());
    },
  );

  test('late prompt confirmation is re-anchored before its response', () {
    final events = <TranscriptEvent>[
      submitted('late-user', 'fast prompt'),
      AssistantMessageCommitted(
        eventId: 'server:assistant:fast',
        sessionId: session,
        ts: base.add(const Duration(milliseconds: 1)),
        messageId: 'fast-response',
        replyTo: 'late-user',
        text: 'fast response',
      ),
      UserMessageConfirmed(
        eventId: 'server:user:late',
        sessionId: session,
        ts: base.add(const Duration(milliseconds: 2)),
        clientMessageId: 'late-user',
        text: 'fast prompt',
      ),
    ];

    final live = deriveTranscriptProjection(sessionId: session, events: events);
    final replayed = deriveTranscriptProjection(
      sessionId: session,
      events: [...events, ...events],
    );

    expect(live.messages.map((message) => message.id), [
      'late-user',
      'fast-response',
    ]);
    expect(
      replayed.messages.map((message) => message.id),
      live.messages.map((message) => message.id),
    );
  });

  test('failed steering clears pending and materializes one failed row', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [
        UserMessageSubmitted(
          eventId: 'local:steer-fail',
          sessionId: session,
          ts: base,
          clientMessageId: 'steer-fail',
          text: 'will fail',
          awaitingPickup: true,
        ),
        failed('steer-fail', 'not accepted'),
      ],
    );

    expect(projection.steering, isA<NoSteering>());
    expect(projection.messages, [
      const UserMsg(
        id: 'steer-fail',
        text: 'will fail',
        status: UserMsgStatus.failed,
      ),
    ]);
  });

  test('authoritative same id confirms an optimistic send in place', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [submitted('cli_1', 'hello'), confirmed('cli_1', 'hello')],
    );

    expect(projection.messages, [const UserMsg(id: 'cli_1', text: 'hello')]);
  });

  test('timeout is suppressed by late authoritative confirmation', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [
        submitted('cli_1', 'hello'),
        failed('cli_1', 'send timed out'),
        confirmed('cli_1', 'hello'),
      ],
    );

    expect(projection.messages, [const UserMsg(id: 'cli_1', text: 'hello')]);
  });

  test(
    'timeout failure clears on acceptance before semantic pickup, then delivers',
    () {
      final reducer = TranscriptProjectionReducer.empty(sessionId: session);
      final steeringSubmission = UserMessageSubmitted(
        eventId: 'local:steer-timeout',
        sessionId: session,
        ts: base,
        clientMessageId: 'steer-timeout',
        text: 'eventual steering delivery',
        awaitingPickup: true,
      );
      final timeout = failed('steer-timeout', 'send timed out');
      final accepted = UserMessageConfirmed(
        eventId: 'server:accepted:steer-timeout',
        sessionId: session,
        ts: base.add(const Duration(seconds: 1)),
        clientMessageId: 'steer-timeout',
        text: 'eventual steering delivery',
        streamingBehavior: UserMessageStreamingBehavior.steer,
        semanticPickup: false,
      );
      final pickup = confirmed('steer-timeout', 'eventual steering delivery');

      expect(
        reducer.applyAll([steeringSubmission, timeout]).projection.messages,
        [
          const UserMsg(
            id: 'steer-timeout',
            text: 'eventual steering delivery',
            status: UserMsgStatus.failed,
          ),
        ],
      );
      final afterAcceptance = reducer.applyAll([accepted]).projection;
      expect(
        afterAcceptance.messages,
        isEmpty,
        reason: 'an accepted message awaiting pickup must not stay failed',
      );
      expect(
        afterAcceptance.steering,
        const SteeringPending(
          clientMessageId: 'steer-timeout',
          text: 'eventual steering delivery',
        ),
      );

      final afterPickup = reducer.applyAll([pickup]).projection;
      expect(afterPickup.messages, [
        const UserMsg(id: 'steer-timeout', text: 'eventual steering delivery'),
      ]);
      expect(afterPickup.steering, isA<NoSteering>());
    },
  );

  test(
    'timeout marks pending local send failed while no confirmation exists',
    () {
      final projection = deriveTranscriptProjection(
        sessionId: session,
        events: [
          submitted('cli_1', 'hello'),
          failed('cli_1', 'send timed out'),
        ],
      );

      expect(projection.messages, [
        const UserMsg(id: 'cli_1', text: 'hello', status: UserMsgStatus.failed),
      ]);
      expect(projection.turn.status, AppTurnStatus.error);
    },
  );

  test('foreign device authoritative message appears in server prefix', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [confirmed('other_1', 'from another owner')],
    );

    expect(projection.messages, [
      const UserMsg(id: 'other_1', text: 'from another owner'),
    ]);
  });

  test(
    'production user → agent message → tool request order stays cancellable',
    () {
      final projection = deriveTranscriptProjection(
        sessionId: session,
        events: [
          confirmed('primary', 'inspect the repo'),
          AssistantMessageCommitted(
            eventId: 'server:assistant:before-tool',
            sessionId: session,
            ts: base.add(const Duration(milliseconds: 1)),
            messageId: 'assistant-before-tool',
            replyTo: 'primary',
            text: 'I will inspect it.',
          ),
          ToolRequested(
            eventId: 'server:tool:req:t1',
            sessionId: session,
            ts: base.add(const Duration(milliseconds: 2)),
            toolCallId: 't1',
            tool: 'Bash',
            args: const {'command': 'pwd'},
          ),
        ],
      );
      final status = ChatStatusProjection(
        transport: const ChatTransportOnline(roomId: 'main'),
        turn: projection.turn.toAppProjection(),
        steering: projection.steering,
      );

      expect(projection.streaming, isNull);
      expect(projection.turn.status, AppTurnStatus.awaitingTool);
      expect(status.canCancel, isTrue);
      expect(status.turn.cancelTargetId, 'primary');
    },
  );

  test('tool request and result collapse into one projected tool row', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [
        ToolRequested(
          eventId: 'server:tool:req:t1',
          sessionId: session,
          ts: base,
          toolCallId: 't1',
          tool: 'Bash',
          args: const {'command': 'pwd'},
        ),
        ToolFinished(
          eventId: 'server:tool:done:t1',
          sessionId: session,
          ts: base,
          toolCallId: 't1',
          result: 'ok',
        ),
      ],
    );

    expect(projection.messages, [
      const ToolEvent(
        id: 't1',
        toolCallId: 't1',
        tool: 'Bash',
        args: {'command': 'pwd'},
        status: ToolEventStatus.completed,
        result: 'ok',
      ),
    ]);
    final tool = projection.messages.single as ToolEvent;
    expect(tool.tool, 'Bash');
    expect(tool.args, {'command': 'pwd'});
    expect(tool.status, ToolEventStatus.completed);
    expect(tool.result, 'ok');
    expect(tool.error, isNull);
  });

  test('streaming deltas finalize on committed assistant message', () {
    final streaming = deriveTranscriptProjection(
      sessionId: session,
      events: [
        AssistantDeltaReceived(
          eventId: 'server:delta:1',
          sessionId: session,
          ts: base,
          replyTo: 'cli_1',
          delta: 'he',
        ),
        AssistantDeltaReceived(
          eventId: 'server:delta:2',
          sessionId: session,
          ts: base,
          replyTo: 'cli_1',
          delta: 'llo',
        ),
      ],
    );

    expect(
      streaming.streaming,
      const StreamingMessage(inReplyTo: 'cli_1', buffer: 'hello'),
    );
    expect(streaming.turn.status, AppTurnStatus.streaming);

    final committed = deriveTranscriptProjection(
      sessionId: session,
      events: [
        ...[
          AssistantDeltaReceived(
            eventId: 'server:delta:1',
            sessionId: session,
            ts: base,
            replyTo: 'cli_1',
            delta: 'he',
          ),
          AssistantDeltaReceived(
            eventId: 'server:delta:2',
            sessionId: session,
            ts: base,
            replyTo: 'cli_1',
            delta: 'llo',
          ),
        ],
        AssistantMessageCommitted(
          eventId: 'server:assistant:a1',
          sessionId: session,
          ts: base,
          messageId: 'a1',
          replyTo: 'cli_1',
          text: 'hello',
        ),
      ],
    );

    expect(committed.streaming, isNull);
    expect(committed.messages, [const AssistantMsg(id: 'a1', text: 'hello')]);
    expect(committed.turn.status, AppTurnStatus.idle);
  });

  test('assistant done clears streaming and converges idle', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [
        AssistantDeltaReceived(
          eventId: 'server:delta:1',
          sessionId: session,
          ts: base,
          replyTo: 'cli_1',
          delta: 'hello',
        ),
        AssistantDoneReceived(
          eventId: 'server:done:cli_1',
          sessionId: session,
          ts: base,
          replyTo: 'cli_1',
        ),
      ],
    );

    expect(projection.streaming, isNull);
    expect(projection.turn.status, AppTurnStatus.idle);
  });

  test('compaction projects a system row', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [
        CompactionRecorded(
          eventId: 'server:compaction:1',
          sessionId: session,
          ts: base,
          summary: 'Short summary',
          tokensBefore: 123,
        ),
      ],
    );

    expect(projection.messages, [
      const CompactionMsg(
        id: 'server:compaction:1',
        summary: 'Short summary',
        tokensBefore: 123,
      ),
    ]);
  });

  test('duplicate server replay is idempotent by event id and message id', () {
    final event = confirmed('cli_1', 'hello');
    final sameMessageDifferentEventId = UserMessageConfirmed(
      eventId: 'server:user:cli_1:replay-2',
      sessionId: session,
      ts: base,
      clientMessageId: 'cli_1',
      text: 'hello again',
    );
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [event, event, sameMessageDifferentEventId],
    );

    expect(projection.messages, [const UserMsg(id: 'cli_1', text: 'hello')]);
  });

  test('session-id filtering ignores foreign transcript events', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [
        confirmed('cli_1', 'hello'),
        confirmed('foreign', 'nope', s: 'sess-b'),
        submitted('foreign-pending', 'nope', s: 'sess-b'),
      ],
    );

    expect(projection.messages, [const UserMsg(id: 'cli_1', text: 'hello')]);
    expect(projection.turn.sessionId, session);
  });

  test(
    'result-before-request retains terminal tool outcome and request metadata',
    () {
      final projection = deriveTranscriptProjection(
        sessionId: session,
        events: [
          ToolFinished(
            eventId: 'server:tool:done:early',
            sessionId: session,
            ts: base.add(const Duration(milliseconds: 20)),
            toolCallId: 'early',
            result: 'completed before request replay',
          ),
          ToolRequested(
            eventId: 'server:tool:req:early',
            sessionId: session,
            ts: base.add(const Duration(milliseconds: 10)),
            toolCallId: 'early',
            tool: 'Read',
            args: const {'path': '/tmp/input'},
          ),
        ],
      );

      expect(projection.messages, hasLength(1));
      expect(
        projection.messages.single,
        isA<ToolEvent>()
            .having((tool) => tool.tool, 'tool', 'Read')
            .having((tool) => tool.args, 'args', const {'path': '/tmp/input'})
            .having((tool) => tool.status, 'status', ToolEventStatus.completed)
            .having(
              (tool) => tool.result,
              'result',
              'completed before request replay',
            ),
      );
    },
  );

  test('incremental reducer stays equivalent across every event variant', () {
    final events = <TranscriptEvent>[
      submitted('cli_1', 'hello'),
      AssistantDeltaReceived(
        eventId: 'server:delta:1',
        sessionId: session,
        ts: base.add(const Duration(milliseconds: 10)),
        replyTo: 'cli_1',
        delta: 'working',
      ),
      ToolRequested(
        eventId: 'server:tool:req:t1',
        sessionId: session,
        ts: base.add(const Duration(milliseconds: 20)),
        toolCallId: 't1',
        tool: 'Bash',
        args: const {'command': 'pwd'},
      ),
      ToolFinished(
        eventId: 'server:tool:done:t1',
        sessionId: session,
        ts: base.add(const Duration(milliseconds: 30)),
        toolCallId: 't1',
        result: 'ok',
      ),
      AssistantMessageCommitted(
        eventId: 'server:assistant:a1',
        sessionId: session,
        ts: base.add(const Duration(milliseconds: 40)),
        messageId: 'a1',
        replyTo: 'cli_1',
        text: 'done',
      ),
      confirmed('cli_1', 'hello'),
      failed('cli_1', 'late ignored failure'),
      AssistantDoneReceived(
        eventId: 'server:done:cli_1',
        sessionId: session,
        ts: base.add(const Duration(milliseconds: 50)),
        replyTo: 'cli_1',
      ),
      CompactionRecorded(
        eventId: 'server:compaction:1',
        sessionId: session,
        ts: base.add(const Duration(milliseconds: 60)),
        summary: 'summary',
      ),
    ];
    final reducer = TranscriptProjectionReducer.empty(sessionId: session);
    final prefix = <TranscriptEvent>[];

    for (final event in events) {
      prefix.add(event);
      final update = reducer.applyAll(<TranscriptEvent>[event]);
      _expectProjectionEquivalent(
        update.projection,
        deriveTranscriptProjection(sessionId: session, events: prefix),
      );
      expect(update.acceptedEvents, <TranscriptEvent>[event]);
    }

    final duplicate = reducer.applyAll(<TranscriptEvent>[events.first]);
    expect(duplicate.acceptedEvents, isEmpty);
    expect(duplicate.firstChangedMessageIndex, isNull);
    expect(
      () => reducer.projection.messages.add(
        const AssistantMsg(id: 'mutate', text: 'not allowed'),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => reducer.projection.messageTimestamps.add(base),
      throwsUnsupportedError,
    );
  });

  test(
    'seeded adversarial histories match clean folds for every partition',
    () {
      for (final seed in <int>[7, 42, 8080]) {
        final events = _adversarialHistory(
          seed: seed,
          sessionId: session,
          base: base,
        );
        final irregular = _irregularPartitions(events.length, seed);
        for (final partitions in <List<int>>[
          <int>[events.length],
          List<int>.filled(events.length, 1),
          irregular,
        ]) {
          _expectPartitionedProjectionEquivalent(
            events: events,
            partitions: partitions,
            sessionId: session,
            seed: seed,
          );
        }
      }
    },
  );

  group('shared transcript projection fixtures', () {
    test(
      'optimistic send, authoritative echo, tool, done, and replay converge',
      () {
        final fixture = _fixtureNamed('optimistic-send-authoritative-replay');
        final projection = deriveTranscriptProjection(
          sessionId: fixture.sessionId,
          events: fixture.events,
        );

        expect(_appProjectionMessages(projection), fixture.expectedMessages);
        expect(projection.streaming, isNull);
        expect(projection.turn.status.name, fixture.expectedTurnStatus);
        expect(projection.turn.working, isFalse);
      },
    );

    test(
      'negative and convergence fixture pins filtering and idle recovery',
      () {
        final fixture = _fixtureNamed('convergence-negative-cases');
        final projection = deriveTranscriptProjection(
          sessionId: fixture.sessionId,
          events: fixture.events,
        );

        expect(_appProjectionMessages(projection), fixture.expectedMessages);
        expect(projection.streaming, isNull);
        expect(projection.turn.status.name, fixture.expectedTurnStatus);
        expect(projection.turn.working, isFalse);
        expect(
          projection.messages.whereType<UserMsg>().map((m) => m.id),
          isNot(contains('foreign_negative')),
        );
      },
    );

    test(
      'reconnect replay fixture is additive, deduped, and session-scoped',
      () {
        final fixture = _fixtureNamed(
          'reconnect-history-is-replay-not-replace',
        );
        final projection = deriveTranscriptProjection(
          sessionId: fixture.sessionId,
          events: fixture.events,
        );

        expect(_appProjectionMessages(projection), fixture.expectedMessages);
        expect(projection.streaming, isNull);
        expect(projection.turn.status.name, fixture.expectedTurnStatus);
        expect(projection.turn.working, isTrue);
        expect(
          projection.messages.whereType<UserMsg>().map((m) => m.id),
          isNot(contains('foreign_1')),
        );
      },
    );
  });
}

List<TranscriptEvent> _adversarialHistory({
  required int seed,
  required String sessionId,
  required DateTime base,
}) {
  final offsets = List<int>.generate(24, (index) => index)
    ..shuffle(Random(seed));
  DateTime ts(int index) => base.add(Duration(milliseconds: offsets[index]));

  final primary = UserMessageConfirmed(
    eventId: 'server:user:primary:$seed',
    sessionId: sessionId,
    ts: ts(7),
    clientMessageId: 'primary-$seed',
    text: 'primary prompt $seed',
  );
  final duplicateMessageId = UserMessageConfirmed(
    eventId: 'server:user:primary-duplicate:$seed',
    sessionId: sessionId,
    ts: ts(8),
    clientMessageId: 'primary-$seed',
    text: 'duplicate must not replace authority',
  );
  final resultBeforeRequest = ToolFinished(
    eventId: 'server:tool:done:$seed',
    sessionId: sessionId,
    ts: ts(10),
    toolCallId: 'tool-$seed',
    result: 'ok-$seed',
  );

  return <TranscriptEvent>[
    UserMessageSubmitted(
      eventId: 'local:primary:$seed',
      sessionId: sessionId,
      ts: ts(15),
      clientMessageId: 'primary-$seed',
      text: 'primary prompt $seed',
    ),
    AssistantMessageCommitted(
      eventId: 'server:assistant:early:$seed',
      sessionId: sessionId,
      ts: ts(1),
      messageId: 'assistant-early-$seed',
      replyTo: 'primary-$seed',
      text: 'early reply',
    ),
    resultBeforeRequest,
    ToolRequested(
      eventId: 'server:tool:req:$seed',
      sessionId: sessionId,
      ts: ts(2),
      toolCallId: 'tool-$seed',
      tool: 'Bash',
      args: <String, Object?>{'command': 'seed-$seed'},
    ),
    primary,
    primary,
    duplicateMessageId,
    AssistantMessageCommitted(
      eventId: 'server:assistant:repeat:$seed',
      sessionId: sessionId,
      ts: ts(0),
      messageId: 'assistant-repeat-$seed',
      replyTo: 'primary-$seed',
      text: 'another reply to the same prompt',
    ),
    UserMessageSubmitted(
      eventId: 'local:steer:$seed',
      sessionId: sessionId,
      ts: ts(11),
      clientMessageId: 'steer-$seed',
      text: 'steer $seed',
      awaitingPickup: true,
    ),
    UserMessageConfirmed(
      eventId: 'server:steer-accepted:$seed',
      sessionId: sessionId,
      ts: ts(9),
      clientMessageId: 'steer-$seed',
      text: 'steer $seed',
      streamingBehavior: UserMessageStreamingBehavior.steer,
      semanticPickup: false,
    ),
    AssistantDeltaReceived(
      eventId: 'server:delta:$seed',
      sessionId: sessionId,
      ts: ts(4),
      replyTo: 'primary-$seed',
      delta: 'partial-$seed',
    ),
    UserMessageSubmitted(
      eventId: 'local:failed:$seed',
      sessionId: sessionId,
      ts: ts(13),
      clientMessageId: 'failed-$seed',
      text: 'failure candidate',
    ),
    UserMessageFailed(
      eventId: 'local:failed-terminal:$seed',
      sessionId: sessionId,
      ts: ts(12),
      clientMessageId: 'failed-$seed',
      code: 'send_timeout',
      message: 'timeout-$seed',
    ),
    CompactionRecorded(
      eventId: 'server:compaction:first:$seed',
      sessionId: sessionId,
      ts: ts(6),
      summary: 'first compaction $seed',
      tokensBefore: 1000 + seed,
    ),
    UserMessageConfirmed(
      eventId: 'server:steer-pickup:$seed',
      sessionId: sessionId,
      ts: ts(5),
      clientMessageId: 'steer-$seed',
      text: 'steer $seed',
    ),
    AssistantDoneReceived(
      eventId: 'server:done:$seed',
      sessionId: sessionId,
      ts: ts(3),
      replyTo: 'steer-$seed',
    ),
    CompactionRecorded(
      eventId: 'server:compaction:second:$seed',
      sessionId: sessionId,
      ts: ts(14),
      summary: 'second compaction $seed',
    ),
    UserMessageConfirmed(
      eventId: 'foreign:user:$seed',
      sessionId: 'foreign-$sessionId',
      ts: ts(16),
      clientMessageId: 'foreign-$seed',
      text: 'must be ignored',
    ),
    resultBeforeRequest,
  ];
}

List<int> _irregularPartitions(int length, int seed) {
  final random = Random(seed ^ 0x5eed);
  final partitions = <int>[];
  var remaining = length;
  while (remaining > 0) {
    final size = 1 + random.nextInt(min(remaining, 5));
    partitions.add(size);
    remaining -= size;
  }
  return partitions;
}

void _expectPartitionedProjectionEquivalent({
  required List<TranscriptEvent> events,
  required List<int> partitions,
  required String sessionId,
  required int seed,
}) {
  final reducer = TranscriptProjectionReducer.empty(sessionId: sessionId);
  final prefix = <TranscriptEvent>[];
  var cursor = 0;
  for (final size in partitions) {
    final previous = reducer.projection;
    final batch = events.sublist(cursor, cursor + size);
    prefix.addAll(batch);
    final update = reducer.applyAll(batch);
    final clean = deriveTranscriptProjection(
      sessionId: sessionId,
      events: prefix,
    );
    final expectedFirstChanged = _firstChangedProjectionIndex(previous, clean);
    expect(
      update.firstChangedMessageIndex,
      expectedFirstChanged,
      reason: 'seed=$seed partitions=$partitions prefix=${prefix.length}',
    );
    _expectProjectionEquivalent(update.projection, clean);
    if (expectedFirstChanged != null) {
      expect(
        update.projection.messages.skip(expectedFirstChanged),
        clean.messages.skip(expectedFirstChanged),
        reason: 'materialized suffix drift: seed=$seed prefix=${prefix.length}',
      );
      expect(
        update.projection.messageTimestamps.skip(expectedFirstChanged),
        clean.messageTimestamps.skip(expectedFirstChanged),
        reason: 'timestamp suffix drift: seed=$seed prefix=${prefix.length}',
      );
    }
    cursor += size;
  }
  expect(cursor, events.length);
}

int? _firstChangedProjectionIndex(
  TranscriptProjection previous,
  TranscriptProjection next,
) {
  final shared = min(previous.messages.length, next.messages.length);
  for (var index = 0; index < shared; index += 1) {
    if (!_sameProjectedMessage(
          previous.messages[index],
          next.messages[index],
        ) ||
        previous.messageTimestamps[index] != next.messageTimestamps[index]) {
      return index;
    }
  }
  return previous.messages.length == next.messages.length ? null : shared;
}

bool _sameProjectedMessage(ChatMessage left, ChatMessage right) {
  if (left is ToolEvent && right is ToolEvent) {
    return left.id == right.id &&
        left.toolCallId == right.toolCallId &&
        left.tool == right.tool &&
        left.args.toString() == right.args.toString() &&
        left.status == right.status &&
        left.result.toString() == right.result.toString() &&
        left.error == right.error;
  }
  return left == right;
}

void _expectProjectionEquivalent(
  TranscriptProjection incremental,
  TranscriptProjection clean,
) {
  expect(incremental.messages, clean.messages);
  expect(incremental.messageTimestamps, clean.messageTimestamps);
  expect(incremental.streaming, clean.streaming);
  expect(incremental.turn.status, clean.turn.status);
  expect(incremental.turn.sessionId, clean.turn.sessionId);
  expect(incremental.turn.turnId, clean.turn.turnId);
  expect(incremental.turn.replyTo, clean.turn.replyTo);
  expect(incremental.turn.error, clean.turn.error);
  expect(incremental.steering, clean.steering);
}

final class _TranscriptFixture {
  const _TranscriptFixture({
    required this.name,
    required this.sessionId,
    required this.events,
    required this.expectedMessages,
    required this.expectedTurnStatus,
  });

  final String name;
  final String sessionId;
  final List<TranscriptEvent> events;
  final List<Map<String, Object?>> expectedMessages;
  final String expectedTurnStatus;
}

_TranscriptFixture _fixtureNamed(String name) {
  final file = File(
    '${Directory.current.parent.path}/.orchestration/contracts/transcript_projection_fixtures.json',
  );
  final root = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final fixtures = root['fixtures'] as List<Object?>;
  final raw = fixtures.cast<Map<String, Object?>>().singleWhere(
    (fixture) => fixture['name'] == name,
  );
  final projection = raw['projection'] as Map<String, Object?>;
  final turn = projection['turn'] as Map<String, Object?>;
  return _TranscriptFixture(
    name: raw['name'] as String,
    sessionId: raw['session_id'] as String,
    events: (raw['events'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(_eventFromJson)
        .toList(growable: false),
    expectedMessages: (projection['messages'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(_appExpectedMessage)
        .toList(growable: false),
    expectedTurnStatus: turn['status'] as String,
  );
}

TranscriptEvent _eventFromJson(Map<String, Object?> json) {
  final eventId = json['event_id'] as String;
  final sessionId = json['session_id'] as String;
  final ts = DateTime.utc(2026, 1, 1);
  return switch (json['kind'] as String) {
    'user_submitted' => UserMessageSubmitted(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      clientMessageId: json['clientMessageId'] as String,
      text: json['text'] as String,
    ),
    'user_confirmed' => UserMessageConfirmed(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      clientMessageId: json['clientMessageId'] as String,
      text: json['text'] as String,
    ),
    'user_failed' => UserMessageFailed(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      clientMessageId: json['clientMessageId'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
    ),
    'assistant_delta' => AssistantDeltaReceived(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      replyTo: json['replyTo'] as String,
      delta: json['delta'] as String,
    ),
    'assistant_committed' => AssistantMessageCommitted(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      messageId: json['messageId'] as String,
      replyTo: json['replyTo'] as String,
      text: json['text'] as String,
    ),
    'assistant_done' => AssistantDoneReceived(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      replyTo: json['replyTo'] as String,
    ),
    'tool_requested' => ToolRequested(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      toolCallId: json['toolCallId'] as String,
      tool: json['tool'] as String,
      args:
          (json['args'] as Map<String, Object?>?) ?? const <String, Object?>{},
    ),
    'tool_finished' => ToolFinished(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      toolCallId: json['toolCallId'] as String,
      result: json['result'],
      error: json['error'] as String?,
    ),
    'compaction_recorded' => CompactionRecorded(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      summary: json['summary'] as String,
      tokensBefore: (json['tokensBefore'] as num?)?.toInt(),
    ),
    final kind => throw UnsupportedError('Unknown fixture event kind: $kind'),
  };
}

List<Map<String, Object?>> _appProjectionMessages(
  TranscriptProjection projection,
) => projection.messages
    .map((message) {
      return switch (message) {
        UserMsg() => {
          'role': 'user',
          'id': message.id,
          'status': message.status.name,
          'text': message.text,
        },
        AssistantMsg() => {
          'role': 'assistant',
          'id': message.id,
          'text': message.text,
        },
        ToolEvent() => {
          'role': 'tool',
          'id': message.id,
          'toolCallId': message.toolCallId,
          'tool': message.tool,
          'status': message.status.name,
          'result': message.result,
        },
        CompactionMsg() => {
          'role': 'system',
          'id': message.id,
          'summary': message.summary,
          'tokensBefore': message.tokensBefore,
        },
      };
    })
    .toList(growable: false);

Map<String, Object?> _appExpectedMessage(Map<String, Object?> message) {
  return switch (message['role'] as String) {
    'user' => {
      'role': 'user',
      'id': message['id'],
      'status': message['status'],
      'text': message['text'],
    },
    'assistant' => {
      'role': 'assistant',
      'id': message['id'],
      'text': message['text'],
    },
    'tool' => {
      'role': 'tool',
      'id': message['id'],
      'toolCallId': message['toolCallId'],
      'tool': message['tool'],
      'status': message['status'],
      'result': message['result'],
    },
    'system' => {
      'role': 'system',
      'id': message['id'],
      'summary': message['summary'],
      'tokensBefore': message['tokensBefore'],
    },
    final role => throw UnsupportedError('Unknown fixture role: $role'),
  };
}

# Pattern: Snapshot Replay to Event Log Mappers

## Rationale

Several protocol seams hydrate state from authoritative snapshots (history pages, legacy message snapshots, `get_messages`) by first emitting canonical transcript events. Keeping these as pure functions that turn transport payloads into an append-only event list gives one stable input for projections and lets every consumer reuse the same convergence logic.

## When to use

Use this pattern when a transport payload is a snapshot/replay payload (or legacy compatibility payload) that eventually drives user-visible history:
- parse and validate input shapes once,
- emit canonical events with deterministic identifiers,
- return a complete event list and let a projection fold the list later.

## When not to use

Don’t use it when data is already domain model shaped and can be consumed directly; don’t duplicate event conversion inside UI widgets or long-running adapters.

## Examples

### Example 1: App-side `session_history` hydrate adapter

**File:** `app/lib/data/sync/session_history_replay.dart:19`

```dart
List<TranscriptEvent> sessionHistoryToTranscriptEvents({
  required SessionHistory history,
  required String sessionId,
}) {
  if (sessionId.isEmpty) {
    throw ArgumentError.value(sessionId, 'sessionId', 'SessionHistory replay requires a canonical session id');
  }

  return <TranscriptEvent>[
    for (final event in history.events)
      sessionHistoryEventToTranscriptEvent(event, sessionId: sessionId),
  ];
}
```

### Example 2: Extension compatibility + legacy snapshot adapter

**File:** `pi-extension/src/session/transcript_projection.ts:145-236`

```ts
export function mapLegacyAgentMessagesToTranscriptEvents(input: LegacyAdapterInput): TranscriptEvent[] {
  const events: TranscriptEvent[] = [];
  let lastUserId: string | null = null;
  for (const [messageIndex, message] of input.messages.entries()) {
    const ts = typeof message.timestamp === "number" ? message.timestamp : 0;
    if (message.role === "compaction" || message.role === "compactionSummary") {
      const summary = message.role === "compactionSummary"
        ? (typeof message.summary === "string" ? message.summary : "")
        : (typeof message.content === "string" ? message.content : "");
      events.push({
        kind: "compaction_recorded",
        eventId: deterministicTranscriptEventId(input.sessionId, "compaction_recorded", String(ts)),
        sessionId: input.sessionId,
        ts,
        summary,
        tokensBefore: typeof message.tokensBefore === "number" ? message.tokensBefore : 0,
      });
    } else if (message.role === "user") {
      const clientMessageId = `sync_${ts}`;
      lastUserId = clientMessageId;
      const images = imagesFromContent(message.content);
      events.push({
        kind: "user_confirmed",
        eventId: deterministicTranscriptEventId(input.sessionId, "user_confirmed", clientMessageId),
        sessionId: input.sessionId,
        ts,
        clientMessageId,
        text: stringifyContent(message.content),
        ...(images.length > 0 ? { images } : {}),
      });
```

The adapter continues with assistant/tool branches in the same function; each
canonical event uses `deterministicTranscriptEventId` rather than a local
sequence, so replay preserves stable identity.

### Example 3: Cockpit RPC `get_messages` hydrator

**File:** `cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart:133`

```dart
List<CockpitTranscriptEvent> transcriptEvents(
  Object? data, {
  required String sessionId,
}) {
  if (data is! Map || data['messages'] is! List) {
    return const <CockpitTranscriptEvent>[];
  }
  final events = <CockpitTranscriptEvent>[];
  for (final raw in data['messages'] as List) {
    if (raw is! Map) continue;
    switch (raw['role']) {
      case 'user':
        final text = _contentText(raw['content']);
        if (text.isNotEmpty) {
          final eventId = nextEventId();
          events.add(
            CockpitUserMessageConfirmed(
              eventId: eventId,
              sessionId: effectiveSessionId,
              ts: ts,
              clientMessageId: raw['id'] as String? ?? eventId,
              text: text,
            ),
          );
        }
      case 'assistant':
        final content = raw['content'];
        if (content is! List) break;
        final messageId = raw['id'] as String? ?? '';
        for (final block in content) {
          if (block is! Map) continue;
          switch (block['type']) {
            case 'text':
              final text = block['text'] as String? ?? '';
              if (text.isNotEmpty) {
                final eventId = nextEventId();
                events.add(
                  CockpitAssistantMessageCommitted(
                    eventId: eventId,
                    sessionId: effectiveSessionId,
                    ts: ts,
                    messageId: messageId.isNotEmpty ? messageId : eventId,
                    replyTo: messageId,
                    text: text,
                  ),
                );
              }
            case 'toolCall':
              final id = block['id'] as String? ?? '';
              events.add(
                CockpitToolRequested(
                  eventId: nextEventId(),
                  sessionId: effectiveSessionId,
                  ts: ts,
                  toolCallId: id,
                  tool: block['name'] as String? ?? '?',
                  args: _asObjectMap(block['arguments']),
                ),
              );
          }
        }
      case 'toolResult':
        final resultText = _contentText(raw['content']);
        events.add(
          CockpitToolFinished(
            eventId: nextEventId(),
            sessionId: effectiveSessionId,
            ts: ts,
            toolCallId: raw['toolCallId'] as String? ?? '',
            result: resultText,
            error: raw['isError'] == true ? resultText : null,
          ),
        );
    }
  }
  return List<CockpitTranscriptEvent>.unmodifiable(events);
}
```

## Common violations

- Mutating or publishing derived UI state directly inside the snapshot adapter.
- Reusing session-local auto-increment IDs instead of deterministic IDs derived from stable server fields.
- Performing projection in multiple code paths (UI, sync, tests) and allowing divergence.

## Index entry

- **snapshot-replay-event-mappers**: Convert protocol snapshots/legacy payloads into canonical event lists before projection to avoid divergent replay behavior across consumers.
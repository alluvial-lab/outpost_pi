# Pattern: Era-Aware Authority Fallback Binding

## Rationale

During a durable-transcript migration, one session can contain both new extension-owned entries and older SDK messages or timestamp-less frames. Durable facts are authoritative when present, but legacy facts remain useful when no durable counterpart exists. The safe bridge is to bind only the matching fallback by a stable collision key, suppress that fallback, and retain unmatched legacy history. A blanket "new path wins" switch would either duplicate facts or erase pre-migration content.

## When to use

Use at a mixed-era replay or live-frame boundary:

1. Decode and index valid durable facts first.
2. Produce a fallback event for the legacy representation.
3. Match only equivalent facts (event id, message id, tool-call id, timestamp, or content signature as appropriate).
4. Suppress the claimed fallback while keeping unmatched legacy facts.
5. Use the legacy timestamp/id path only when the durable-era marker is absent; do not invent durable authority.

## When not to use

Do not use fallback binding to merge semantically different events or to hide malformed durable data. Invalid durable entries must fail validation, while genuinely unmatched legacy entries should remain visible under their legacy identity.

## Examples

### Example 1: Extension reconciliation indexes durable facts before SDK fallback

**File:** `pi-extension/src/session/transcript_projection.ts:271-330`

```ts
for (const [index, entry] of input.entries.entries()) {
  const decoded = decodeDurableTranscriptEntry(entry);
  if (decoded.status !== "decoded" || durableEventIds.has(decoded.event.eventId)) continue;
  const event = { ...decoded.event, sessionId: input.sessionId } as TranscriptEvent;
  decodedByIndex.set(index, event);
  durableEventIds.add(event.eventId);
  // Index tool, assistant-message, and compaction collision keys too.
}

const fallbackByIndex = indexPreDurableContextEvents(input.sessionId, input.entries);
const claimedFallbackUserIndexes = bindDurableUserClaims(decodedByIndex, fallbackByIndex);
for (const [index, entry] of input.entries.entries()) {
  const durable = decodedByIndex.get(index);
  if (durable) {
    output.push(durable);
    continue;
  }
  // Emit only fallback events not claimed by a durable counterpart.
}
```

Durable entries win their own positions, while the fallback stream survives for unmatched SDK messages and legacy compaction entries.

### Example 2: Timestamped assistant frames use durable-era identity; old frames keep a fallback

**File:** `app/lib/data/sync/sync_service.dart:1291-1345`

```dart
if (ts != null) {
  final stableKey = messageId ?? inReplyTo;
  _runDetachedTranscriptWrite(
    () => _appendTranscriptEvent(
      AssistantMessageCommitted(
        eventId: serverReplayEventId(sessionId, agentMessageWireType, stableKey, ts),
        messageId: serverReplayMessageId(sessionId, agentMessageWireType, stableKey, ts),
        // ...
      ),
    ),
  );
} else {
  _runDetachedTranscriptWrite(
    () => _appendTranscriptEvent(
      AssistantMessageCommitted(
        eventId: 'server:assistant_message:$inReplyTo:${uuid7()}',
        messageId: 'agent_$inReplyTo',
        // ... legacy phone-clock path
      ),
    ),
  );
}
```

The deterministic path is used only when the extension supplies its durable-era timestamp; a pre-durable extension is not forced into a fabricated replay identity.

### Example 3: User echoes bind to the replay identity only when the server supplies `ts`

**File:** `app/lib/data/sync/sync_service.dart:1361-1412`

```dart
final userEventId = ts != null
    ? serverReplayUserEventId(
        _activeTranscriptSessionId(),
        messageType,
        ts,
      )
    : 'server:user_confirmed:$id';

_runDetachedTranscriptWrite(
  () => _appendTranscriptEvent(
    UserMessageConfirmed(
      eventId: userEventId,
      sessionId: _activeTranscriptSessionId(),
      ts: ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : DateTime.now(),
      // ...
    ),
  ),
);
```

This lets a new live echo collapse with `session_history`, while an early or old echo remains usable instead of being discarded.

### Example 4: Error frames preserve the same durable/legacy split

**File:** `app/lib/data/sync/sync_service.dart:1629-1668`

```dart
if (ts != null) {
  _runDetachedTranscriptWrite(
    () => _appendTranscriptEvent(
      errorDiagnosticToTranscriptEvent(
        sessionId: _activeTranscriptSessionId(),
        ts: ts,
        inReplyTo: inReplyTo,
        code: code,
        message: message,
      ),
    ),
    expectedRef: expectedRef,
  );
} else {
  // A ts-less frame is a pre-durable extension. Preserve the legacy
  // phone-clock path because no authoritative history fact can arrive.
  _runDetachedTranscriptWrite(
    () => _appendTranscriptEvents(<TranscriptEvent>[
      AssistantMessageCommitted(
        eventId: 'server:error_message:${uuid7()}',
        sessionId: _activeTranscriptSessionId(),
        ts: diagnosticTs,
        messageId: 'err_${uuid7()}',
        replyTo: inReplyTo ?? 'error',
        text: '$code: $message',
      ),
      AssistantDoneReceived(
        eventId: 'server:error_done:${uuid7()}',
        sessionId: _activeTranscriptSessionId(),
        ts: diagnosticTs,
        replyTo: inReplyTo ?? 'error',
      ),
    ]),
    expectedRef: expectedRef,
  );
}
```

The error path follows the same migration rule as assistant and user messages, so durable replay and pre-durable live behavior do not diverge silently.

### Example 5: Tests prove durable authority and unmatched fallback coexist

**File:** `pi-extension/src/session/transcript_projection.test.ts:163-251,313-353`

```ts
expect(reopened).toEqual(durableEvents);
expect(projectSessionHistory({ sessionId, events: reopened, limit: 10 }))
  .toEqual(projectSessionHistory({ sessionId, events: durableEvents, limit: 10 }));

// A legacy tool request remains alongside a distinct durable mesh pair.
expect(reopened.map((event) => [event.kind, "toolCallId" in event ? event.toolCallId : null]))
  .toEqual([
    ["tool_requested", "legacy-call"],
    ["tool_requested", "mesh_envelope-1"],
    ["tool_finished", "mesh_envelope-1"],
  ]);
```

## Common violations

- Dropping every SDK fallback as soon as one durable entry is present.
- Emitting both durable and fallback representations for the same message under different ids.
- Treating a missing timestamp as proof that a frame is corrupt when it is a supported pre-durable shape.
- Matching repeated equal-content user messages FIFO across migration boundaries instead of binding the nearest valid durable claim.

## Related

- `single-source-live-identity.md` — the stable identity rule once the durable-era source exists.
- `snapshot-replay-event-mappers.md` — canonical mapping for authoritative history payloads.
- `canonical-projection-equivalence-oracle.md` — tests that the migration path projects like the canonical path.

# Pattern: Durable-First Visibility Gating

## Rationale

Transcript facts are replayed from durable history after reconnect and reopen, so live visibility must not become authoritative before the same fact has crossed the durable persistence boundary. Producers construct one canonical event, append it through the persistence seam, accept only `recorded` or `duplicate` as authoritative, and then publish the live frame using the persisted timestamp/identity. A failed append suppresses replayable transcript visibility; control errors may still be sent, but they must not claim a durable timestamp.

This keeps a late `session_sync` equivalent to the live path instead of creating a live-only row or a replay-only row.

## When to use

Use for any user-visible event that is later reconstructed from a session log:

1. Build the canonical event and stable identity first.
2. Append/commit it through the injected persistence boundary.
3. Treat `recorded` and idempotent `duplicate` as authoritative; stop on unavailable/failed persistence.
4. Read the stored timestamp when forming the live frame, then broadcast/send.
5. Keep non-transcript control signaling explicit when it must remain available during a persistence failure.

## When not to use

Do not delay purely ephemeral streaming hints, room liveness, or turn-state convergence behind transcript storage. Do not treat a best-effort diagnostic notification as a durable transcript fact unless its append succeeded.

## Examples

### Example 1: The transcript aggregate installs only after append succeeds

**File:** `pi-extension/src/session/transcript_event_log.ts:37-50`

```ts
record(event: TranscriptEvent): TranscriptRecordResult {
  if (this.byIdentity.has(eventIdentity(event))) return { status: "duplicate" };
  const persistence = this.persistence;
  if (!persistence) return { status: "unavailable" };
  try {
    encodeDurableTranscriptEventV1(event);
    persistence.append(event);
  } catch {
    return { status: "failed" };
  }
  this.install(event);
  return { status: "recorded" };
}
```

`install` is the in-memory authority and is deliberately after `persistence.append`; a failed writer cannot make an event appear in subsequent history projection.

### Example 2: SDK user and assistant facts gate their broadcasts on the record result

**File:** `pi-extension/src/session/sdk_session_projection.ts:505-522,540-557`

```ts
const recorded = this.transcriptLog.record({
  kind: "user_confirmed",
  eventId,
  sessionId,
  ts: canonicalTs,
  clientMessageId,
  text,
});
if (recorded.status !== "recorded" && recorded.status !== "duplicate") return;
this.opts.outputs.broadcast(this.currentSessionMessage({
  type: SERVER_MESSAGE_DISCRIMINATORS.user_input,
  id: clientMessageId,
  text,
  ts: this.recordedTranscriptTs(eventId) ?? canonicalTs,
}));
```

The assistant branch uses the same record-result gate before emitting `agent_message`, so live SDK backfill and `session_history` share one authority.

### Example 3: Native tool hooks persist both edges before owner fan-out

**File:** `pi-extension/src/index.ts:1448-1460,1475-1497`

```ts
const recorded = _recordDurableTranscriptEvent({
  kind: "tool_requested",
  eventId,
  sessionId,
  ts: producedAt,
  toolCallId: event.toolCallId,
  tool: event.toolName,
  args,
});
if (!_isAuthoritativeTranscriptRecord(recorded) || _owners.activeCount() === 0) return;
const ts = _sdkSessionProjection.recordedTranscriptTs(eventId) ?? producedAt;
_owners.broadcast(_withCurrentSession({
  type: "tool_request",
  tool_call_id: event.toolCallId,
  tool: event.toolName,
  args,
  ts,
}));
```

`tool_execution_end` repeats the same ordering for the result/error frame. Persistence failure therefore cannot create a live tool card that disappears on reopen.

### Example 4: Mesh request/result pairs require durable authority before either is visible

**File:** `pi-extension/src/index.ts:2260-2304`

```ts
const requestRecorded = _recordDurableTranscriptEvent({
  kind: "tool_requested",
  eventId: requestEventId,
  sessionId,
  ts: requestTs,
  toolCallId,
  tool: "agent-network",
  args,
});
if (!_isAuthoritativeTranscriptRecord(requestRecorded)) return;

let finishRecorded = _recordDurableTranscriptEvent({
  kind: "tool_finished",
  eventId: finishEventId,
  sessionId,
  ts: finishTs,
  toolCallId,
  result: finishResult,
});
let finishError: string | undefined;
if (!_isAuthoritativeTranscriptRecord(finishRecorded)) {
  finishError = "mesh transcript result persistence failed";
  finishRecorded = _recordDurableTranscriptEvent({
    kind: "tool_finished",
    eventId: finishEventId,
    sessionId,
    ts: finishTs,
    toolCallId,
    error: finishError,
  });
}
if (!_isAuthoritativeTranscriptRecord(finishRecorded)) return;

_owners.broadcast(_withCurrentSession({
  type: "tool_request",
  tool_call_id: toolCallId,
  tool: "agent-network",
  args,
  ts: requestTs,
}));
```

The pair is persisted as a unit from the viewer's perspective: no request or result is broadcast until both durable facts are available.

### Example 5: Error sends distinguish control visibility from durable transcript authority

**File:** `pi-extension/src/index.ts:796-816`

```ts
const recorded = _recordDurableTranscriptEvent({
  kind: "provider_error",
  eventId,
  sessionId,
  ts: producedAt,
  code,
  message,
});
const authoritative = _isAuthoritativeTranscriptRecord(recorded);
const error = _withCurrentSession({
  type: "error",
  code,
  message,
  ...(authoritative
    ? { ts: _sdkSessionProjection.recordedTranscriptTs(eventId) ?? producedAt }
    : {}),
});
if (sender) sender.send(error);
else _owners.broadcast(error);
```

The error remains an immediate control signal even if persistence is unavailable, but the wire frame carries a replay-correlating timestamp only when durable authority exists.

## Common violations

- Broadcasting before the append returns, then allowing a later history replay to create a second row.
- Adding the event to an in-memory log before a failed SDK/storage write.
- Treating every append result as authoritative instead of distinguishing `failed`/`unavailable` from `duplicate`.
- Applying the transcript gate to independent `working=false` or transport-error convergence and leaving the UI stuck when storage is degraded.

## Related

- `snapshot-replay-event-mappers.md` — converts authoritative snapshots into canonical events.
- `single-source-live-identity.md` — keeps live and replay identity aligned.
- `edge-triggered-convergence.md` — suppresses repeated semantic side effects after authority is established.

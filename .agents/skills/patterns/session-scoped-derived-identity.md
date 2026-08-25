# Pattern: Session-Scoped Derived Identity

## Rationale

A transcript identity is meaningful only inside the session that owns it. The active session id must therefore be present at reads, writes, dedupe lookups, and derived-link reconstruction. Mutable helpers such as "last user" and ingress idempotency state are rebuilt from the current session's events or keyed by session id; they are never allowed to bleed across `/new`, `/resume`, `/fork`, or reopen boundaries.

This pattern covers data and derived identity. The concrete owner/channel guard for transient resources such as uploads is the separate `owner-channel-scoped-resource-ownership.md` pattern.

## When to use

Use whenever a value links transcript facts, responses, retries, or local storage:

1. Capture or receive the canonical session id at the boundary.
2. Include it in the storage key and event identity, or filter by it before deriving state.
3. Key idempotency/reservation indexes by session rather than by client id alone.
4. Clear or recompute session-derived caches when the session changes.
5. Verify the scope again when reading persisted records or applying a late callback.

## When not to use

Do not add a session dimension to process-global configuration, machine identity, or a deliberately owner/channel-scoped transport resource. Do not use a cached session id as a substitute for a lifecycle generation or concrete channel check.

## Examples

### Example 1: History reads filter the event log by the current session

**File:** `pi-extension/src/session/sdk_session_projection.ts:596-601`

```ts
const sessionId = this.currentRemoteSessionId();
const projection = projectSessionHistory({
  sessionId,
  events: this.transcriptLog.forSession(sessionId),
  limit: effectiveLimit,
});
```

The log may retain more than one branch during a process lifetime, but a `session_history` response cannot project a foreign branch.

### Example 2: Derived reply attribution is recomputed from scoped events

**File:** `pi-extension/src/session/sdk_session_projection.ts:1102-1107`

```ts
private recomputeLastTranscriptUserId(): void {
  const currentSessionEvents = this.transcriptLog.forSession(this.currentRemoteSessionId());
  const lastUser = [...currentSessionEvents].reverse().find((event) =>
    event.kind === "user_confirmed" || event.kind === "user_submitted"
  );
  this.lastTranscriptUserId = lastUser?.clientMessageId ?? null;
}
```

After hydration or replacement, the assistant's `replyTo` is rebuilt from the active branch instead of inheriting the previous session's last user.

### Example 3: Ingress idempotency is keyed by session identity

**File:** `pi-extension/src/session/sdk_session_projection.ts:171-178,472-484`

```ts
// clientMessageIds already delivered in each session
private readonly deliveredUserMessageIds = new Map<string, Set<string>>();

wasUserMessageDelivered(sessionId: string, clientMessageId: string): boolean {
  return this.deliveredUserMessageIds.get(sessionId)?.has(clientMessageId) ?? false;
}

recordDeliveredUserMessageId(sessionId: string, clientMessageId: string): void {
  (this.deliveredUserMessageIds.get(sessionId)
    ?? this.deliveredUserMessageIds.set(sessionId, new Set<string>()).get(sessionId)!)
    .add(clientMessageId);
}
```

The same app id may legitimately be reused after a session replacement without suppressing the new session's delivery.

### Example 4: App transcript storage carries the full remote session key

**File:** `app/lib/data/sync/sync_service.dart:1983-1993` and `app/lib/data/local/transcript_event_store_hive.dart:18-28`

```dart
TranscriptSessionKey _transcriptKeyForRef(RemoteSessionRef ref) =>
    TranscriptSessionKey(
      peerId: ref.peerEpk,
      roomId: ref.roomId,
      sessionId: ref.sessionId,
    );

for (final event in batch) {
  if (event.sessionId != key.sessionId) {
    throw StateError('transcript event belongs to another session');
  }
}
```

The app refuses to append an event under a different session box, making the scope check an adapter invariant rather than a UI convention.

### Example 5: Session replacement clears ephemeral identity caches

**File:** `pi-extension/src/session/sdk_session_projection.ts:1095-1099`

```ts
private clearTranscriptOnly(): void {
  this.transcriptLog.clear();
  this.deliveredUserEventIds.clear();
  this.deliveredUserMessageIds.clear();
  this.lastTranscriptUserId = null;
}
```

Clearing the derived indexes together prevents an old branch from influencing a fresh session while the durable store remains available for explicit historical reads.

## Common violations

- Looking up `lastTranscriptUserId` from all retained events instead of the active session.
- Keying ingress dedupe, pending sends, or transcript rows only by client message id.
- Reusing a session-scoped cache after replacement without clearing or recomputing it.
- Treating owner id as sufficient for a resource whose channel can be replaced; use the owner/channel-scoped pattern for that case.

## Related

- `owner-channel-scoped-resource-ownership.md` — adds concrete channel identity to retained owner resources.
- `generation-fenced-async-ownership.md` — prevents a stale async continuation from mutating a newly active session.
- `single-source-live-identity.md` — aligns stable message identity across live and replay paths.

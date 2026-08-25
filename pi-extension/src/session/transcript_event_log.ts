import { encodeDurableTranscriptEventV1 } from "./durable_transcript_event.js";
import type { TranscriptEvent } from "./transcript_event.js";

/** Persist one validated canonical transcript event at the current session boundary. */
export interface TranscriptEventPersistence {
  append(event: TranscriptEvent): void;
}

/** Report whether a durable record became authoritative in the transcript aggregate. */
export type TranscriptRecordResult =
  | { status: "recorded" }
  | { status: "duplicate" }
  | { status: "unavailable" }
  | { status: "failed" };

/**
 * Append-only transcript aggregate with persistence-before-visibility semantics.
 *
 * Durable recording fails closed: an event enters the authoritative in-memory
 * projection only after the injected session writer returns successfully.
 * Hydration installs the reconciled active branch without writing it again.
 */
export class TranscriptEventLog {
  private readonly events: TranscriptEvent[] = [];
  private readonly byIdentity = new Map<string, TranscriptEvent>();
  private persistence: TranscriptEventPersistence | null = null;

  /** Bind the current session writer used to make new events durable. */
  bindPersistence(persistence: TranscriptEventPersistence): void {
    this.persistence = persistence;
  }

  /**
   * Unbind the current writer without clearing the hydrated transcript.
   *
   * When a writer is supplied, an obsolete lifecycle owner is ignored unless
   * it is still the bound writer; this prevents an old session callback from
   * disabling a replacement writer.
   */
  unbindPersistence(persistence?: TranscriptEventPersistence): void {
    if (persistence !== undefined && persistence !== this.persistence) return;
    this.persistence = null;
  }

  /**
   * Append one event after validation and persistence, then expose it in memory.
   *
   * Returns `duplicate` for an existing session/event identity, `unavailable`
   * when no writer is bound, and `failed` when validation or persistence
   * rejects the event. Only `recorded` and `duplicate` establish durable
   * authority for live visibility.
   */
  record(event: TranscriptEvent): TranscriptRecordResult {
    if (this.byIdentity.has(eventIdentity(event))) return { status: "duplicate" };
    const persistence = this.persistence;
    if (!persistence) return { status: "unavailable" };
    try {
      // Validate before crossing the persistence boundary. The SDK adapter
      // performs the same encoding to obtain the custom-entry payload.
      encodeDurableTranscriptEventV1(event);
      persistence.append(event);
    } catch {
      return { status: "failed" };
    }
    this.install(event);
    return { status: "recorded" };
  }

  /** Install a validated durable snapshot without writing it back to storage. */
  hydrate(events: readonly TranscriptEvent[]): number {
    let appended = 0;
    for (const event of events) {
      if (this.install(event)) appended++;
    }
    return appended;
  }

  /** Return the timestamp for a known session/event identity, or `undefined` when absent. */
  recordedTsFor(sessionId: string, eventId: string): number | undefined {
    return this.byIdentity.get(eventIdentity({ sessionId, eventId }))?.ts;
  }

  /** Report whether live producers can currently cross the durable session boundary. */
  hasPersistence(): boolean {
    return this.persistence !== null;
  }

  /** Replace the in-memory aggregate with a hydrated snapshot, without persistence writes. */
  replace(events: readonly TranscriptEvent[]): void {
    this.clear();
    this.hydrate(events);
  }

  /** Clear the in-memory aggregate while leaving the bound persistence adapter untouched. */
  clear(): void {
    this.events.length = 0;
    this.byIdentity.clear();
  }

  /** Return the current session-scoped event view in insertion order. */
  forSession(sessionId: string): readonly TranscriptEvent[] {
    return this.events.filter((event) => event.sessionId === sessionId);
  }

  /** Return a detached snapshot of all hydrated and newly recorded events. */
  entries(): readonly TranscriptEvent[] {
    return [...this.events];
  }

  private install(event: TranscriptEvent): boolean {
    const identity = eventIdentity(event);
    if (this.byIdentity.has(identity)) return false;
    this.byIdentity.set(identity, event);
    this.events.push(event);
    return true;
  }
}

function eventIdentity(event: Pick<TranscriptEvent, "sessionId" | "eventId">): string {
  return JSON.stringify([event.sessionId, event.eventId]);
}

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

  bindPersistence(persistence: TranscriptEventPersistence): void {
    this.persistence = persistence;
  }

  unbindPersistence(persistence?: TranscriptEventPersistence): void {
    if (persistence !== undefined && persistence !== this.persistence) return;
    this.persistence = null;
  }

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

  hydrate(events: readonly TranscriptEvent[]): number {
    let appended = 0;
    for (const event of events) {
      if (this.install(event)) appended++;
    }
    return appended;
  }

  recordedTsFor(sessionId: string, eventId: string): number | undefined {
    return this.byIdentity.get(eventIdentity({ sessionId, eventId }))?.ts;
  }

  /** Report whether live producers can currently cross the durable session boundary. */
  hasPersistence(): boolean {
    return this.persistence !== null;
  }

  replace(events: readonly TranscriptEvent[]): void {
    this.clear();
    this.hydrate(events);
  }

  clear(): void {
    this.events.length = 0;
    this.byIdentity.clear();
  }

  forSession(sessionId: string): readonly TranscriptEvent[] {
    return this.events.filter((event) => event.sessionId === sessionId);
  }

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

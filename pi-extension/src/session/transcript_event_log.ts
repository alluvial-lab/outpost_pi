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
 * Hydration and the explicitly named legacy fallback never write again.
 */
export class TranscriptEventLog {
  private readonly events: TranscriptEvent[] = [];
  private readonly byEventId = new Map<string, TranscriptEvent>();
  private readonly fallbackEventIds = new Set<string>();
  private persistence: TranscriptEventPersistence | null = null;

  bindPersistence(persistence: TranscriptEventPersistence): void {
    this.persistence = persistence;
  }

  unbindPersistence(persistence?: TranscriptEventPersistence): void {
    if (persistence !== undefined && persistence !== this.persistence) return;
    this.persistence = null;
  }

  record(event: TranscriptEvent): TranscriptRecordResult {
    const existing = this.byEventId.get(event.eventId);
    const upgradesFallback = existing !== undefined && this.fallbackEventIds.has(event.eventId);
    if (existing && !upgradesFallback) return { status: "duplicate" };
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
    if (upgradesFallback) this.replaceFallback(event);
    else this.install(event);
    return { status: "recorded" };
  }

  appendFallback(event: TranscriptEvent): boolean {
    const installed = this.install(event);
    if (installed) this.fallbackEventIds.add(event.eventId);
    return installed;
  }

  hydrate(events: readonly TranscriptEvent[]): number {
    let appended = 0;
    for (const event of events) {
      if (this.install(event)) appended++;
    }
    return appended;
  }

  recordedTsFor(eventId: string): number | undefined {
    return this.byEventId.get(eventId)?.ts;
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
    this.byEventId.clear();
    this.fallbackEventIds.clear();
  }

  forSession(sessionId: string): readonly TranscriptEvent[] {
    return this.events.filter((event) => event.sessionId === sessionId);
  }

  entries(): readonly TranscriptEvent[] {
    return [...this.events];
  }

  /** Transitional alias for F1-era producers; F4 removes legacy re-derivation. */
  append(event: TranscriptEvent): boolean {
    return this.appendFallback(event);
  }

  /** Transitional alias for existing hydration callers. */
  appendAll(events: readonly TranscriptEvent[]): number {
    return this.hydrate(events);
  }

  private install(event: TranscriptEvent): boolean {
    if (this.byEventId.has(event.eventId)) return false;
    this.byEventId.set(event.eventId, event);
    this.events.push(event);
    return true;
  }

  private replaceFallback(event: TranscriptEvent): void {
    const index = this.events.findIndex((candidate) => candidate.eventId === event.eventId);
    if (index < 0) throw new Error("fallback transcript index is inconsistent");
    this.events[index] = event;
    this.byEventId.set(event.eventId, event);
    this.fallbackEventIds.delete(event.eventId);
  }
}

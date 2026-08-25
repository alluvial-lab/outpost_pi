import { describe, expect, test, vi } from "vitest";
import type { TranscriptEvent } from "./transcript_event.js";
import { TranscriptEventLog, type TranscriptEventPersistence } from "./transcript_event_log.js";

function user(eventId: string, ts: number, text = "hello"): TranscriptEvent {
  return {
    kind: "user_confirmed",
    eventId,
    sessionId: "session-1",
    ts,
    clientMessageId: `client-${eventId}`,
    text,
  };
}

describe("TranscriptEventLog durable aggregate", () => {
  test("persists before visibility and installs the event only after append returns", () => {
    const log = new TranscriptEventLog();
    const event = user("event-1", 10);
    const append = vi.fn(() => {
      expect(log.entries()).toEqual([]);
      expect(log.recordedTsFor(event.sessionId, event.eventId)).toBeUndefined();
    });
    log.bindPersistence({ append });

    expect(log.record(event)).toEqual({ status: "recorded" });
    expect(append).toHaveBeenCalledWith(event);
    expect(log.entries()).toEqual([event]);
    expect(log.recordedTsFor(event.sessionId, event.eventId)).toBe(10);
  });

  test("deduplicates before persistence and preserves the first event and timestamp", () => {
    const log = new TranscriptEventLog();
    const append = vi.fn();
    log.bindPersistence({ append });

    expect(log.record(user("same", 10, "first"))).toEqual({ status: "recorded" });
    expect(log.record(user("same", 20, "second"))).toEqual({ status: "duplicate" });
    expect(append).toHaveBeenCalledTimes(1);
    expect(log.entries()).toEqual([user("same", 10, "first")]);
    expect(log.recordedTsFor("session-1", "same")).toBe(10);
  });

  test("reports unavailable and failed persistence without installing authority", () => {
    const log = new TranscriptEventLog();
    const event = user("event-1", 10);
    expect(log.record(event)).toEqual({ status: "unavailable" });

    const failing: TranscriptEventPersistence = { append: () => { throw new Error("disk full"); } };
    log.bindPersistence(failing);
    expect(log.record(event)).toEqual({ status: "failed" });
    expect(log.entries()).toEqual([]);
    expect(log.recordedTsFor(event.sessionId, event.eventId)).toBeUndefined();
  });

  test("invalid runtime events fail before persistence", () => {
    const log = new TranscriptEventLog();
    const append = vi.fn();
    log.bindPersistence({ append });

    expect(log.record({ ...user("event-1", 10), ts: Number.NaN })).toEqual({ status: "failed" });
    expect(append).not.toHaveBeenCalled();
    expect(log.entries()).toEqual([]);
  });

  test("hydrate installs reconciled first-writer-wins events without persisting", () => {
    const log = new TranscriptEventLog();
    const append = vi.fn();
    log.bindPersistence({ append });

    expect(log.hydrate([
      user("hydrated", 2),
      user("hydrated", 99),
      { ...user("other-session", 3), sessionId: "session-2" },
    ])).toBe(2);
    expect(append).not.toHaveBeenCalled();
    expect(log.recordedTsFor("session-1", "hydrated")).toBe(2);
    expect(log.forSession("session-1").map((event) => event.eventId)).toEqual(["hydrated"]);
  });

  test("event identity is scoped to its owning session", () => {
    const log = new TranscriptEventLog();
    const parent = user("copied-event", 10);
    const fork = { ...parent, sessionId: "session-2" };

    expect(log.hydrate([parent, fork])).toBe(2);
    expect(log.forSession("session-1")).toEqual([parent]);
    expect(log.forSession("session-2")).toEqual([fork]);
    expect(log.recordedTsFor("session-1", "copied-event")).toBe(10);
    expect(log.recordedTsFor("session-2", "copied-event")).toBe(10);
  });

  test("unbind can be conditional and a fresh binding restores recording", () => {
    const log = new TranscriptEventLog();
    const first = { append: vi.fn() };
    const second = { append: vi.fn() };
    log.bindPersistence(first);
    log.unbindPersistence(second);
    expect(log.record(user("still-bound", 1))).toEqual({ status: "recorded" });

    log.unbindPersistence(first);
    expect(log.record(user("unbound", 2))).toEqual({ status: "unavailable" });
    log.bindPersistence(second);
    expect(log.record(user("fresh", 3))).toEqual({ status: "recorded" });
  });

  test("replace and clear rebuild both event and timestamp indexes", () => {
    const log = new TranscriptEventLog();
    log.hydrate([user("old", 1)]);
    log.replace([user("new", 2), user("new", 3)]);

    expect(log.entries()).toEqual([user("new", 2)]);
    expect(log.recordedTsFor("session-1", "old")).toBeUndefined();
    expect(log.recordedTsFor("session-1", "new")).toBe(2);

    log.clear();
    expect(log.entries()).toEqual([]);
    expect(log.recordedTsFor("session-1", "new")).toBeUndefined();
  });
});

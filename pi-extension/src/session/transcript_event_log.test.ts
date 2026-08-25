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
      expect(log.recordedTsFor(event.eventId)).toBeUndefined();
    });
    log.bindPersistence({ append });

    expect(log.record(event)).toEqual({ status: "recorded" });
    expect(append).toHaveBeenCalledWith(event);
    expect(log.entries()).toEqual([event]);
    expect(log.recordedTsFor(event.eventId)).toBe(10);
  });

  test("deduplicates before persistence and preserves the first event and timestamp", () => {
    const log = new TranscriptEventLog();
    const append = vi.fn();
    log.bindPersistence({ append });

    expect(log.record(user("same", 10, "first"))).toEqual({ status: "recorded" });
    expect(log.record(user("same", 20, "second"))).toEqual({ status: "duplicate" });
    expect(append).toHaveBeenCalledTimes(1);
    expect(log.entries()).toEqual([user("same", 10, "first")]);
    expect(log.recordedTsFor("same")).toBe(10);
  });

  test("a durable hook fact upgrades an earlier SDK fallback with the same identity", () => {
    const log = new TranscriptEventLog();
    const append = vi.fn();
    log.bindPersistence({ append });
    expect(log.appendFallback(user("same", 10, "sdk timestamp"))).toBe(true);

    const hookOwned = user("same", 20, "hook timestamp");
    expect(log.record(hookOwned)).toEqual({ status: "recorded" });
    expect(append).toHaveBeenCalledWith(hookOwned);
    expect(log.entries()).toEqual([hookOwned]);
    expect(log.recordedTsFor("same")).toBe(20);
    expect(log.record(hookOwned)).toEqual({ status: "duplicate" });
    expect(append).toHaveBeenCalledTimes(1);
  });

  test("reports unavailable and failed persistence without installing authority", () => {
    const log = new TranscriptEventLog();
    const event = user("event-1", 10);
    expect(log.record(event)).toEqual({ status: "unavailable" });

    const failing: TranscriptEventPersistence = { append: () => { throw new Error("disk full"); } };
    log.bindPersistence(failing);
    expect(log.record(event)).toEqual({ status: "failed" });
    expect(log.entries()).toEqual([]);
    expect(log.recordedTsFor(event.eventId)).toBeUndefined();
  });

  test("invalid runtime events fail before persistence", () => {
    const log = new TranscriptEventLog();
    const append = vi.fn();
    log.bindPersistence({ append });

    expect(log.record({ ...user("event-1", 10), ts: Number.NaN })).toEqual({ status: "failed" });
    expect(append).not.toHaveBeenCalled();
    expect(log.entries()).toEqual([]);
  });

  test("fallback and hydrate install first-writer-wins events without persisting", () => {
    const log = new TranscriptEventLog();
    const append = vi.fn();
    log.bindPersistence({ append });

    expect(log.appendFallback(user("fallback", 1))).toBe(true);
    expect(log.hydrate([
      user("fallback", 99),
      user("hydrated", 2),
      { ...user("other-session", 3), sessionId: "session-2" },
    ])).toBe(2);
    expect(append).not.toHaveBeenCalled();
    expect(log.recordedTsFor("fallback")).toBe(1);
    expect(log.recordedTsFor("hydrated")).toBe(2);
    expect(log.forSession("session-1").map((event) => event.eventId)).toEqual(["fallback", "hydrated"]);
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
    expect(log.recordedTsFor("old")).toBeUndefined();
    expect(log.recordedTsFor("new")).toBe(2);

    log.clear();
    expect(log.entries()).toEqual([]);
    expect(log.recordedTsFor("new")).toBeUndefined();
  });
});

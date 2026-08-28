import { describe, expect, test, vi } from "vitest";
import type { EventBus } from "@earendil-works/pi-coding-agent";
import { BackgroundActivityTracker } from "./background_activity.js";

type Handler = (payload: unknown) => void;

class FakeEventBus implements EventBus {
  readonly handlers = new Map<string, Set<Handler>>();
  readonly registrationCount = new Map<string, number>();

  on(channel: string, handler: Handler): () => void {
    const listeners = this.handlers.get(channel) ?? new Set<Handler>();
    this.handlers.set(channel, listeners);
    this.registrationCount.set(channel, (this.registrationCount.get(channel) ?? 0) + 1);
    listeners.add(handler);
    return () => listeners.delete(handler);
  }

  emit(channel: string, payload: unknown): void {
    for (const handler of this.handlers.get(channel) ?? []) handler(payload);
  }
}

describe("BackgroundActivityTracker", () => {
  test("tracks created and terminal lifecycle transitions", () => {
    const changes: number[] = [];
    const tracker = new BackgroundActivityTracker(({ activeCount }) => changes.push(activeCount));
    const bus = new FakeEventBus();
    tracker.subscribe(bus);

    bus.emit("subagents:created", { id: "one" });
    bus.emit("subagents:created", { id: "two" });
    bus.emit("subagents:completed", { id: "one" });
    bus.emit("subagents:failed", { id: "two" });

    expect(tracker.activeCount).toBe(0);
    expect(changes).toEqual([1, 0]);

    bus.emit("subagents:created", { id: "three" });
    bus.emit("subagents:resumed", { id: "three" });
    expect(changes).toEqual([1, 0, 1, 0]);
  });

  test("ignores malformed payloads and never treats child disposal as completion", () => {
    const onChange = vi.fn();
    const tracker = new BackgroundActivityTracker(onChange);
    const bus = new FakeEventBus();
    tracker.subscribe(bus);

    for (const payload of [null, {}, { id: 7 }, [7], ["agent-id"]]) {
      expect(() => bus.emit("subagents:created", payload)).not.toThrow();
      expect(() => bus.emit("subagents:completed", payload)).not.toThrow();
    }
    bus.emit("subagents:created", { id: "live" });
    bus.emit("subagents:child:disposed", { id: "live" });

    expect(tracker.activeCount).toBe(1);
    expect(onChange).toHaveBeenCalledOnce();
  });

  test("emits only on 0-to-n and n-to-0 transitions", () => {
    const changes: number[] = [];
    const tracker = new BackgroundActivityTracker(({ activeCount }) => changes.push(activeCount));
    const bus = new FakeEventBus();
    tracker.subscribe(bus);

    bus.emit("subagents:created", { id: "same" });
    bus.emit("subagents:created", { id: "same" });
    bus.emit("subagents:created", { id: "other" });
    bus.emit("subagents:completed", { id: "unknown" });
    bus.emit("subagents:completed", { id: "same" });
    bus.emit("subagents:failed", { id: "other" });
    bus.emit("subagents:failed", { id: "other" });

    expect(changes).toEqual([1, 0]);
  });

  test("subscribe is idempotent for one bus identity", () => {
    const tracker = new BackgroundActivityTracker(vi.fn());
    const bus = new FakeEventBus();
    tracker.subscribe(bus);
    tracker.subscribe(bus);

    expect(bus.registrationCount.get("subagents:created")).toBe(1);
    expect(bus.registrationCount.get("subagents:completed")).toBe(1);
    expect(bus.registrationCount.get("subagents:failed")).toBe(1);
    expect(bus.registrationCount.get("subagents:resumed")).toBe(1);
  });

  test("clearForSessionBoundary empties activity and emits the idle edge", () => {
    const changes: number[] = [];
    const tracker = new BackgroundActivityTracker(({ activeCount }) => changes.push(activeCount));
    const bus = new FakeEventBus();
    tracker.subscribe(bus);
    bus.emit("subagents:created", { id: "live" });

    tracker.clearForSessionBoundary();
    tracker.clearForSessionBoundary();

    expect(tracker.activeCount).toBe(0);
    expect(changes).toEqual([1, 0]);
  });
});

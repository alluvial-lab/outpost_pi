import { describe, expect, test, vi } from "vitest";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
  createEventBus,
  createExtensionRuntime,
  type EventBus,
  type Extension,
  type ExtensionFactory,
  type ExtensionRuntime,
} from "@earendil-works/pi-coding-agent";
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

type LoadExtensionFromFactory = (
  factory: ExtensionFactory,
  cwd: string,
  eventBus: EventBus,
  runtime: ExtensionRuntime,
  extensionPath?: string,
) => Promise<Extension>;

async function realSdkFactoryLoader(): Promise<LoadExtensionFromFactory> {
  const packageEntry = fileURLToPath(import.meta.resolve("@earendil-works/pi-coding-agent"));
  const loaderUrl = pathToFileURL(join(dirname(packageEntry), "core/extensions/loader.js")).href;
  const module = await import(loaderUrl) as { loadExtensionFromFactory?: LoadExtensionFromFactory };
  if (typeof module.loadExtensionFromFactory !== "function") {
    throw new Error("installed Pi SDK does not expose its factory loader implementation");
  }
  return module.loadExtensionFromFactory;
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

  test("SDK-owned listeners remain safe during awaited shutdown and auto-unregister afterward", async () => {
    const tracker = new BackgroundActivityTracker(vi.fn());
    const eventBus = createEventBus();
    const runtime = createExtensionRuntime();
    let enterShutdown!: () => void;
    let releaseShutdown!: () => void;
    const shutdownEntered = new Promise<void>((resolve) => { enterShutdown = resolve; });
    const shutdownRelease = new Promise<void>((resolve) => { releaseShutdown = resolve; });
    const factory: ExtensionFactory = (pi) => {
      tracker.subscribe(pi.events);
      pi.on("session_shutdown", async () => {
        enterShutdown();
        await shutdownRelease;
      });
    };
    const load = await realSdkFactoryLoader();
    const extension = await load(factory, process.cwd(), eventBus, runtime, "<background-activity-test>");
    const shutdown = extension.handlers.get("session_shutdown")?.[0];
    if (!shutdown) throw new Error("expected session_shutdown test handler");

    const teardown = shutdown({ type: "session_shutdown", reason: "new" });
    await shutdownEntered;
    // AgentSessionRuntime invalidates the old runtime only after this awaited
    // handler finishes, so an event in the teardown window must still be safe.
    eventBus.emit("subagents:created", { id: "during-shutdown" });
    expect(tracker.activeCount).toBe(1);

    releaseShutdown();
    await teardown;
    runtime.invalidate();
    // The installed loader owns pi.events subscriptions and removes this
    // listener when the runtime is invalidated; a late terminal event is ignored.
    eventBus.emit("subagents:completed", { id: "during-shutdown" });
    expect(tracker.activeCount).toBe(1);
  });
});

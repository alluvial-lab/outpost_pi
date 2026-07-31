import { describe, expect, test, vi } from "vitest";
import { createEventBus, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { OutpostPiRuntimePorts } from "./ports.js";
import { createOutpostPiExtensionRuntime } from "./composition_root.js";
import { OutpostPiRuntimeCoordinator } from "./runtime_coordinator.js";

function ports(): OutpostPiRuntimePorts & { sessionStart: ReturnType<typeof vi.fn> } {
  const sessionStart = vi.fn();
  return {
    relay: {
      status: () => "disconnected",
      start: vi.fn(),
      stop: vi.fn(async () => undefined),
      sendRoomMeta: vi.fn(),
      onOuterMessage: vi.fn(() => vi.fn()),
      createPeerChannel: vi.fn(),
      subscribePresence: vi.fn(),
      attachCrossPcBridge: vi.fn(),
      detachCrossPcBridge: vi.fn(),
    },
    owners: {
      activeCount: () => 0,
      attach: vi.fn(),
      detach: vi.fn(),
      broadcast: vi.fn(),
      routeFrom: vi.fn(),
      lateAttachTargets: () => [],
    },
    session: {
      bindApi: vi.fn(),
      onSessionStart: sessionStart,
      bindCommandContext: vi.fn(),
      bindSessionContext: vi.fn(),
      clearStaleContexts: vi.fn(),
      sendPiMessage: vi.fn(() => false),
      wakeAgent: vi.fn(async () => ({ ok: false, detail: "not bound" })),
      publishWorking: vi.fn(),
      resetTurnSnapshot: vi.fn(),
      handleClientMessage: vi.fn(),
    } as OutpostPiRuntimePorts["session"],
    sessionStart,
    commands: {
      register: vi.fn(),
      ensureStarted: vi.fn(),
      prepareSessionShutdown: vi.fn(),
      closeMesh: vi.fn(async () => undefined),
    },
  };
}

function piWithHandlers(): {
  pi: ExtensionAPI;
  handlers: Map<string, (...args: unknown[]) => unknown>;
} {
  const handlers = new Map<string, (...args: unknown[]) => unknown>();
  const pi = {
    events: createEventBus(),
    on: vi.fn((name: string, handler: (...args: unknown[]) => unknown) => {
      handlers.set(name, handler);
    }),
  } as unknown as ExtensionAPI;
  return { pi, handlers };
}

function context(sessionId: string): ExtensionContext {
  return {
    sessionManager: { getSessionId: () => sessionId },
    ui: {},
  } as unknown as ExtensionContext;
}

describe("composition root runtime", () => {
  test("register defers API publication until an approved session_start", () => {
    const p = ports();
    const { pi, handlers } = piWithHandlers();
    const runtime = createOutpostPiExtensionRuntime(pi, p, new OutpostPiRuntimeCoordinator());

    runtime.register();

    expect(p.session.bindApi).not.toHaveBeenCalled();
    expect(pi.on).toHaveBeenCalledWith("session_start", expect.any(Function));
    expect(pi.on).toHaveBeenCalledWith("session_shutdown", expect.any(Function));
    expect(p.commands.register).toHaveBeenCalledWith(pi, runtime);

    const result = handlers.get("session_start")?.({ type: "session_start", reason: "startup" }, context("parent"));
    expect(result).toBeUndefined();
    expect(p.session.bindApi).toHaveBeenCalledWith(pi);
    expect(p.session.bindSessionContext).toHaveBeenCalledOnce();
    expect(p.sessionStart).toHaveBeenCalledOnce();
  });

  test("session_start publishes working=false to clear stale true from a killed predecessor", () => {
    // Regression: when a pi process is killed mid-turn (SIGKILL), session_shutdown
    // never fires, so resetTurnSnapshot() never converges working=false. The
    // relay retains working=true in its room state. The successor process starts
    // idle but must explicitly publish working=false to clear the stale value —
    // resetTurnSnapshot is a no-op on an already-idle projection (false→false
    // publishes nothing via the diff).
    const p = ports();
    const { pi, handlers } = piWithHandlers();
    const runtime = createOutpostPiExtensionRuntime(pi, p, new OutpostPiRuntimeCoordinator());
    runtime.register();

    handlers.get("session_start")?.({ type: "session_start", reason: "startup" }, context("successor"));

    expect(p.session.publishWorking).toHaveBeenCalledWith(false);
  });

  test("duplicate session_start is idempotent and a disposed epoch does not restart", () => {
    const p = ports();
    const { pi, handlers } = piWithHandlers();
    const runtime = createOutpostPiExtensionRuntime(pi, p, new OutpostPiRuntimeCoordinator());
    runtime.register();
    const ctx = context("parent");

    handlers.get("session_start")?.({ type: "session_start", reason: "startup" }, ctx);
    handlers.get("session_start")?.({ type: "session_start", reason: "startup" }, ctx);
    expect(p.session.bindApi).toHaveBeenCalledOnce();
    expect(p.session.bindSessionContext).toHaveBeenCalledOnce();
    expect(p.commands.ensureStarted).toHaveBeenCalledOnce();

    runtime.epoch.dispose();
    handlers.get("session_start")?.({ type: "session_start", reason: "reload" }, context("replacement"));
    expect(p.commands.ensureStarted).toHaveBeenCalledOnce();
  });

  test("owner session_shutdown marks epoch before clearing resources and closing mesh", async () => {
    const p = ports();
    const { pi, handlers } = piWithHandlers();
    const runtime = createOutpostPiExtensionRuntime(pi, p, new OutpostPiRuntimeCoordinator());
    runtime.register();
    handlers.get("session_start")?.({ type: "session_start", reason: "startup" }, context("parent"));

    await handlers.get("session_shutdown")?.({ type: "session_shutdown", reason: "new" });

    expect(runtime.epoch.disposed).toBe(true);
    expect(p.commands.prepareSessionShutdown).toHaveBeenCalledOnce();
    expect(p.session.clearStaleContexts).toHaveBeenCalledWith("new");
    expect(p.relay.detachCrossPcBridge).toHaveBeenCalledOnce();
    expect(p.relay.stop).toHaveBeenCalledOnce();
    expect(p.commands.closeMesh).toHaveBeenCalledOnce();
    const disposeOrder = vi.mocked(p.commands.prepareSessionShutdown!).mock.invocationCallOrder[0]!;
    const clearOrder = vi.mocked(p.session.clearStaleContexts).mock.invocationCallOrder[0]!;
    const stopOrder = vi.mocked(p.relay.stop).mock.invocationCallOrder[0]!;
    const closeMeshOrder = vi.mocked(p.commands.closeMesh!).mock.invocationCallOrder[0]!;
    expect(disposeOrder).toBeLessThan(clearOrder);
    expect(clearOrder).toBeLessThan(stopOrder);
    expect(stopOrder).toBeLessThan(closeMeshOrder);
  });

  test("owner session_shutdown awaits relay drain before closing mesh", async () => {
    const p = ports();
    let release!: () => void;
    const drain = new Promise<void>((resolve) => { release = resolve; });
    p.relay.stop = vi.fn(() => drain);
    const { pi, handlers } = piWithHandlers();
    const runtime = createOutpostPiExtensionRuntime(pi, p, new OutpostPiRuntimeCoordinator());
    runtime.register();
    handlers.get("session_start")?.({ type: "session_start", reason: "startup" }, context("parent"));

    const shutdown = handlers.get("session_shutdown")?.({ type: "session_shutdown", reason: "new" }) as Promise<void>;
    await Promise.resolve();
    expect(p.relay.stop).toHaveBeenCalledOnce();
    expect(p.commands.closeMesh).not.toHaveBeenCalled();

    release();
    await shutdown;
    expect(p.commands.closeMesh).toHaveBeenCalledOnce();
  });

  test("owner session_shutdown converges the turn projection before stopping the relay", async () => {
    const p = ports();
    const { pi, handlers } = piWithHandlers();
    const runtime = createOutpostPiExtensionRuntime(pi, p, new OutpostPiRuntimeCoordinator());
    runtime.register();
    handlers.get("session_start")?.({ type: "session_start", reason: "startup" }, context("parent"));

    await handlers.get("session_shutdown")?.({ type: "session_shutdown", reason: "new" });

    expect(p.session.resetTurnSnapshot).toHaveBeenCalledOnce();
    const resetOrder = vi.mocked(p.session.resetTurnSnapshot!).mock.invocationCallOrder[0]!;
    const stopOrder = vi.mocked(p.relay.stop!).mock.invocationCallOrder[0]!;
    // working=false must be publishable while the relay is still connected,
    // so the turn convergence runs BEFORE relay.stop().
    expect(resetOrder).toBeLessThan(stopOrder);
  });

  test("satellite shutdown cannot tear down owner resources", async () => {
    const coordinator = new OutpostPiRuntimeCoordinator();
    const ownerPorts = ports();
    const ownerPi = piWithHandlers();
    const owner = createOutpostPiExtensionRuntime(ownerPi.pi, ownerPorts, coordinator);
    owner.register();
    ownerPi.handlers.get("session_start")?.({ type: "session_start", reason: "startup" }, context("parent"));

    const satellitePorts = ports();
    const satellitePi = piWithHandlers();
    const satellite = createOutpostPiExtensionRuntime(satellitePi.pi, satellitePorts, coordinator);
    satellite.register();
    satellitePi.handlers.get("session_start")?.({ type: "session_start", reason: "startup" }, context("child"));
    await satellitePi.handlers.get("session_shutdown")?.({ type: "session_shutdown", reason: "quit" });

    expect(satellitePorts.session.clearStaleContexts).not.toHaveBeenCalled();
    expect(satellitePorts.relay.stop).not.toHaveBeenCalled();
    expect(satellitePorts.commands.closeMesh).not.toHaveBeenCalled();
    expect(owner.isOwner()).toBe(true);
  });
});

import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { afterEach, describe, expect, test } from "vitest";
import {
  createEventBus,
  createExtensionRuntime,
  ExtensionRunner,
  SessionManager,
  type EventBus,
  type Extension,
  type ExtensionActions,
  type ExtensionAPI,
  type ExtensionContextActions,
  type ExtensionFactory,
  type ExtensionRuntime,
  type ModelRegistry,
} from "@earendil-works/pi-coding-agent";
import { createOutpostPiExtensionRuntime, type OutpostPiRuntime } from "../extension/composition_root.js";
import type { OutpostPiRuntimePorts } from "../extension/ports.js";
import {
  getOutpostPiRuntimeCoordinator,
  resetOutpostPiRuntimeCoordinatorForTest,
} from "../extension/runtime_coordinator.js";
import { subagentGate } from "./subagent_gate.js";
import {
  SdkSessionReplacementHarness,
  TestPeerChannel,
} from "../../test/support/sdk_session_replacement_harness.js";
import type { ClientMessage, ServerMessage } from "../protocol/types.js";

/**
 * Test split:
 * - The coordinator-contract cases use the installed SDK loader/runtime with
 *   deterministic ports. They prove lease authority, child lifecycle events,
 *   and the SDK's real runtime.assertActive() staleness guard in isolation.
 * - The replacement-gap cases use SdkSessionReplacementHarness, which loads
 *   the real src/index.js factory. They therefore exercise the production
 *   process-global pending-delivery queue and its exact-once drain behavior.
 *
 * We intentionally do not instantiate @gotgenes/pi-subagents' private child
 * AgentSession graph. Child authority is covered through its documented
 * synchronous EventBus contract; production queue behavior is covered through
 * the real Outpost-Pi factory and AgentSessionRuntime replacement lifecycle.
 */

/**
 * This suite deliberately uses the installed SDK's private loader entrypoint.
 * The public package export omits loadExtensionFromFactory, but that function
 * is the production boundary that creates ExtensionAPI methods guarded by the
 * real runtime.assertActive(). The only bypass is resource discovery: the
 * factory is supplied inline rather than loaded from a filesystem path.
 */
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

interface Instance {
  label: string;
  api: ExtensionAPI;
  runtime: OutpostPiRuntime;
  runner: ExtensionRunner;
  sessionId: string;
}

class RealSdkHarness {
  readonly eventBus = createEventBus();
  readonly deliveries: Array<{ label: string; content: unknown }> = [];
  readonly queued: unknown[] = [];
  clears = 0;
  relayStops = 0;
  meshCloses = 0;
  private boundApi: ExtensionAPI | null = null;
  private bindingLabel = "";

  constructor() {
    resetOutpostPiRuntimeCoordinatorForTest();
  }

  async create(label: string): Promise<Instance> {
    const cwd = mkdtempSync(join(tmpdir(), `outpost-pi-${label}-`));
    const sessionManager = SessionManager.create(cwd, join(cwd, "sessions"));
    const sdkRuntime = createExtensionRuntime();
    let api!: ExtensionAPI;
    let remoteRuntime!: OutpostPiRuntime;
    const factory: ExtensionFactory = (factoryApi) => {
      api = factoryApi;
      remoteRuntime = createOutpostPiExtensionRuntime(
        factoryApi,
        this.ports(label),
        getOutpostPiRuntimeCoordinator(),
      );
      remoteRuntime.registerLifecycle();
    };
    const load = await realSdkFactoryLoader();
    const extension = await load(factory, cwd, this.eventBus, sdkRuntime, `<${label}>`);
    const runner = new ExtensionRunner(
      [extension],
      sdkRuntime,
      cwd,
      sessionManager,
      {} as ModelRegistry,
    );
    runner.bindCore(this.actions(label), this.contextActions());
    return { label, api, runtime: remoteRuntime, runner, sessionId: sessionManager.getSessionId() };
  }

  async start(instance: Instance, reason: "startup" | "new" | "reload" = "startup"): Promise<void> {
    await instance.runner.emit({ type: "session_start", reason });
  }

  async shutdown(instance: Instance, reason: "new" | "reload" | "quit" = "new"): Promise<void> {
    await instance.runner.emit({ type: "session_shutdown", reason });
  }

  phoneSend(content: unknown): void {
    if (!this.boundApi) {
      this.queued.push(content);
      return;
    }
    this.boundApi.sendUserMessage(content as string);
  }

  private ports(label: string): OutpostPiRuntimePorts {
    return {
      relay: {
        status: () => "disconnected",
        start: async () => { throw new Error("not used"); },
        stop: () => { this.relayStops += 1; },
        sendRoomMeta: () => undefined,
        onOuterMessage: () => () => undefined,
        attachCrossPcBridge: async () => undefined,
        detachCrossPcBridge: () => undefined,
      },
      owners: {
        activeCount: () => 0,
        attach: () => { throw new Error("not used"); },
        detach: () => undefined,
        broadcast: () => undefined,
        routeFrom: () => undefined,
        lateAttachTargets: () => [],
      },
      session: {
        setRoomId: () => undefined,
        bindApi: (boundApi) => {
          this.boundApi = boundApi;
          this.bindingLabel = label;
          const pending = this.queued.splice(0);
          for (const content of pending) boundApi.sendUserMessage(content as string);
        },
        bindCommandContext: () => undefined,
        bindSessionContext: () => undefined,
        clearStaleContexts: () => {
          this.clears += 1;
          this.boundApi = null;
          this.bindingLabel = "";
        },
        sendPiMessage: () => false,
        wakeAgent: async () => ({ ok: false }),
        publishWorking: () => undefined,
        resetTurnSnapshot: () => undefined,
        handleClientMessage: () => undefined,
      },
      commands: {
        register: () => undefined,
        prepareSessionShutdown: () => undefined,
        closeMesh: async () => { this.meshCloses += 1; },
      },
    };
  }

  private actions(label: string): ExtensionActions {
    return {
      sendMessage: () => undefined,
      sendUserMessage: (content) => { this.deliveries.push({ label, content }); },
      appendEntry: () => undefined,
      setSessionName: () => undefined,
      getSessionName: () => undefined,
      setLabel: () => undefined,
      getActiveTools: () => [],
      getAllTools: () => [],
      setActiveTools: () => undefined,
      refreshTools: () => undefined,
      getCommands: () => [],
      setModel: async () => true,
      getThinkingLevel: () => "off",
      setThinkingLevel: () => undefined,
    };
  }

  private contextActions(): ExtensionContextActions {
    return {
      getModel: () => undefined,
      isIdle: () => true,
      isProjectTrusted: () => true,
      getSignal: () => undefined,
      abort: () => undefined,
      hasPendingMessages: () => false,
      shutdown: () => undefined,
      getContextUsage: () => undefined,
      compact: () => undefined,
      getSystemPrompt: () => "",
    };
  }
}

const productionHarnesses: SdkSessionReplacementHarness[] = [];
const productionCwds: string[] = [];

afterEach(async () => {
  subagentGate.reset();
  for (const harness of productionHarnesses.splice(0).reverse()) {
    await harness.dispose().catch(() => undefined);
  }
  for (const cwd of productionCwds.splice(0).reverse()) {
    rmSync(cwd, { recursive: true, force: true });
  }
});

async function createProductionHarness(): Promise<SdkSessionReplacementHarness> {
  const cwd = mkdtempSync(join(tmpdir(), "outpost-pi-production-queue-"));
  productionCwds.push(cwd);
  const harness = await SdkSessionReplacementHarness.create({ cwd });
  productionHarnesses.push(harness);
  return harness;
}

function userMessage(id: string, sessionId: string, text: string): ClientMessage {
  return { type: "user_message", id, session_id: sessionId, text };
}

function deliveryPendingFor(id: string): (message: ServerMessage) => boolean {
  return (message) => message.type === "error"
    && message.code === "delivery_pending"
    && message.in_reply_to === id;
}

function internalErrorFor(channel: TestPeerChannel, id: string): boolean {
  return channel.sent.some((message) => message.type === "error"
    && message.code === "internal_error"
    && message.in_reply_to === id);
}

describe("OutpostPiRuntimeCoordinator with the real Pi SDK factory/runtime", () => {
  test("stock /new replacement publishes a fresh API and delivers once", async () => {
    const h = new RealSdkHarness();
    const parent = await h.create("parent-old");
    await h.start(parent);
    await h.shutdown(parent, "new");
    parent.runner.invalidate();
    expect(() => parent.api.sendUserMessage("stale-check")).toThrow(/stale/i);

    const successor = await h.create("parent-new");
    await h.start(successor, "new");
    h.phoneSend("from-phone");
    expect(h.deliveries).toEqual([{ label: "parent-new", content: "from-phone" }]);
  });

  test("a live child while the parent is idle cannot replace parent ingress", async () => {
    const h = new RealSdkHarness();
    const parent = await h.create("parent");
    await h.start(parent);
    const child = await h.create("child");
    h.eventBus.emit("subagents:child:session-created", { sessionId: child.sessionId });
    await h.start(child);

    h.phoneSend("parent-only");
    expect(h.deliveries).toEqual([{ label: "parent", content: "parent-only" }]);
  });

  test("after child disposal parent delivery remains armed", async () => {
    const h = new RealSdkHarness();
    const parent = await h.create("parent");
    await h.start(parent);
    const child = await h.create("child");
    h.eventBus.emit("subagents:child:session-created", { sessionId: child.sessionId });
    await h.start(child);
    child.runner.invalidate();
    h.eventBus.emit("subagents:child:disposed", { sessionId: child.sessionId });

    h.phoneSend("still-parent");
    expect(h.deliveries).toEqual([{ label: "parent", content: "still-parent" }]);
    expect(getOutpostPiRuntimeCoordinator().snapshot()).toMatchObject({ kind: "ACTIVE", sessionId: parent.sessionId, childCount: 0 });
  });

  test("four parallel children with out-of-order disposal cannot change owner", async () => {
    const h = new RealSdkHarness();
    const parent = await h.create("parent");
    await h.start(parent);
    const children = await Promise.all([0, 1, 2, 3].map((n) => h.create(`child-${n}`)));
    for (const child of children) {
      h.eventBus.emit("subagents:child:session-created", { sessionId: child.sessionId });
    }
    await Promise.all(children.map((child) => h.start(child)));
    for (const index of [2, 0, 3, 1]) {
      const child = children[index]!;
      child.runner.invalidate();
      h.eventBus.emit("subagents:child:disposed", { sessionId: child.sessionId });
    }

    h.phoneSend("owner-stable");
    expect(h.deliveries).toEqual([{ label: "parent", content: "owner-stable" }]);
    expect(getOutpostPiRuntimeCoordinator().snapshot()).toMatchObject({ kind: "ACTIVE", sessionId: parent.sessionId });
  });

  test("an active content-suppression gate cannot deny a legitimate successor", async () => {
    const h = new RealSdkHarness();
    const parent = await h.create("parent-old");
    await h.start(parent);
    await h.shutdown(parent, "new");
    h.phoneSend("queued-while-subagent-tool-open");

    h.eventBus.emit("subagents:child:session-created", { sessionId: "known-child-session" });
    subagentGate.enter("subagent");
    try {
      expect(subagentGate.isActive()).toBe(true);
      const successor = await h.create("parent-new");
      await h.start(successor, "new");
      expect(getOutpostPiRuntimeCoordinator().snapshot()).toMatchObject({ kind: "ACTIVE", sessionId: successor.sessionId });
      expect(h.deliveries).toEqual([{
        label: "parent-new",
        content: "queued-while-subagent-tool-open",
      }]);
    } finally {
      subagentGate.exit("subagent");
    }
  });

  test("a child during the replacement gap cannot reserve the successor lease", async () => {
    const h = new RealSdkHarness();
    const parent = await h.create("parent-old");
    await h.start(parent);
    await h.shutdown(parent, "new");
    h.phoneSend("queued-gap-message");

    const child = await h.create("gap-child");
    h.eventBus.emit("subagents:child:session-created", { sessionId: child.sessionId });
    await h.start(child);
    const successor = await h.create("parent-new");
    await h.start(successor, "new");

    expect(h.queued).toHaveLength(0);
    expect(h.deliveries).toEqual([{ label: "parent-new", content: "queued-gap-message" }]);
  });

  test("stale predecessor and satellite teardown cannot clear current binding, relay, or queue", async () => {
    const h = new RealSdkHarness();
    const old = await h.create("old");
    await h.start(old);
    await h.shutdown(old, "new");
    const successor = await h.create("successor");
    await h.start(successor, "new");
    const child = await h.create("child");
    h.eventBus.emit("subagents:child:session-created", { sessionId: child.sessionId });
    await h.start(child);
    const baseline = { clears: h.clears, relayStops: h.relayStops, meshCloses: h.meshCloses };

    h.queued.push("sentinel");
    await h.shutdown(old, "quit");
    await h.shutdown(child, "quit");
    expect({ clears: h.clears, relayStops: h.relayStops, meshCloses: h.meshCloses }).toEqual(baseline);
    expect(h.queued).toEqual(["sentinel"]);
    h.queued.length = 0;
    h.phoneSend("current-owner");
    expect(h.deliveries.at(-1)).toEqual({ label: "successor", content: "current-owner" });
  });

  test("duplicate session_start(new) activates and drains pending ingress idempotently", async () => {
    const h = new RealSdkHarness();
    const old = await h.create("old");
    await h.start(old);
    await h.shutdown(old, "new");
    h.phoneSend("queued-once");
    const successor = await h.create("successor");

    await h.start(successor, "new");
    await h.start(successor, "new");
    expect(h.deliveries).toEqual([{ label: "successor", content: "queued-once" }]);
    expect(h.queued).toHaveLength(0);
  });
});

describe("production index pending-delivery queue across SDK replacement", () => {
  test("an active content-suppression gate cannot suppress successor session binding", async () => {
    const harness = await createProductionHarness();
    // createProductionHarness resets the module registry before loading the
    // production index, so resolve the gate from that same registry instance.
    const { subagentGate: productionSubagentGate } = await import("./subagent_gate.js");
    const parentSessionId = harness.currentRemoteSessionId();

    productionSubagentGate.enter("subagent");
    try {
      const paused = await harness.beginPausedNewSession();
      await paused.complete();

      const successorSessionId = harness.currentRemoteSessionId();
      expect(successorSessionId).not.toBe(parentSessionId);
      expect(successorSessionId).toBe(harness.currentSession.sessionManager.getSessionId());
    } finally {
      productionSubagentGate.exit("subagent");
    }
  });

  test("a queued message during a slow replacement does not expire and delivers once the successor re-arms", async () => {
    const harness = await createProductionHarness();
    const restoreTtl = harness.currentModule._setPendingDeliveryTtlForTest(50);
    const sessionId = harness.currentRemoteSessionId();
    const paused = await harness.beginPausedNewSession();

    try {
      expect(getOutpostPiRuntimeCoordinator().isReplacing()).toBe(true);
      const channel = harness.routeCurrent(userMessage("slow-gap", sessionId, "survive slow replacement"));
      await channel.waitForMessage(deliveryPendingFor("slow-gap"));

      await new Promise<void>((resolve) => setTimeout(resolve, 120));
      expect(getOutpostPiRuntimeCoordinator().isReplacing()).toBe(true);
      expect(internalErrorFor(channel, "slow-gap")).toBe(false);
      expect(harness.pendingDeliveryCount()).toBe(1);

      await paused.complete();
      await harness.waitForDelivery((delivery) =>
        delivery.sessionLabel === "replacement-2"
        && delivery.method === "sendUserMessage"
        && delivery.content === "survive slow replacement",
      );
      expect(harness.deliveries.filter((delivery) => delivery.content === "survive slow replacement")).toHaveLength(1);
      expect(harness.pendingDeliveryCount()).toBe(0);
      expect(internalErrorFor(channel, "slow-gap")).toBe(false);
    } finally {
      restoreTtl();
      if (getOutpostPiRuntimeCoordinator().isReplacing()) await paused.complete();
    }
  });

  test("a stuck replacement (successor never re-arms) expires a queued message at the absolute deadline, not forever", async () => {
    // If successor creation failed and the SDK propagated the error while RPC
    // mode stayed alive, the coordinator is permanently REPLACING. The renewed
    // TTL must NOT loop forever: an absolute deadline caps the wait and
    // surfaces a real internal_error. Matches the app-side 60s fallback.
    const harness = await createProductionHarness();
    const restoreTtl = harness.currentModule._setPendingDeliveryTtlForTest(50);
    const restoreDeadline = harness.currentModule._setPendingDeliveryAbsoluteDeadlineForTest(120);
    const sessionId = harness.currentRemoteSessionId();
    const paused = await harness.beginPausedNewSession();

    try {
      expect(getOutpostPiRuntimeCoordinator().isReplacing()).toBe(true);
      const channel = harness.routeCurrent(userMessage("stuck-gap", sessionId, "survive until deadline"));
      await channel.waitForMessage(deliveryPendingFor("stuck-gap"));

      // Past the short TTL (50ms) but before the absolute deadline (120ms):
      // renewed, no internal_error yet.
      await new Promise<void>((resolve) => setTimeout(resolve, 80));
      expect(getOutpostPiRuntimeCoordinator().isReplacing()).toBe(true);
      expect(internalErrorFor(channel, "stuck-gap")).toBe(false);
      expect(harness.pendingDeliveryCount()).toBe(1);

      // Past the absolute deadline: expires to internal_error (not renewed
      // forever). The replacement is still stuck (never completed).
      await channel.waitForMessage((message) => message.type === "error"
        && message.code === "internal_error"
        && message.in_reply_to === "stuck-gap");
      expect(getOutpostPiRuntimeCoordinator().isReplacing()).toBe(true);
      expect(harness.pendingDeliveryCount()).toBe(0);
      expect(harness.deliveries.filter((delivery) => delivery.content === "survive until deadline")).toHaveLength(0);
    } finally {
      restoreDeadline();
      restoreTtl();
      if (getOutpostPiRuntimeCoordinator().isReplacing()) await paused.complete();
    }
  });

  test("a queued message outside replacement still expires to internal_error", async () => {
    const harness = await createProductionHarness();
    const restoreTtl = harness.currentModule._setPendingDeliveryTtlForTest(50);

    try {
      expect(getOutpostPiRuntimeCoordinator().isReplacing()).toBe(false);
      harness.currentModule._setPiForTest(null);
      const channel = harness.routeCurrent(userMessage(
        "broken-binding",
        harness.currentRemoteSessionId(),
        "expire without successor",
      ));

      await channel.waitForMessage(deliveryPendingFor("broken-binding"));
      await channel.waitForMessage((message) => message.type === "error"
        && message.code === "internal_error"
        && message.in_reply_to === "broken-binding");
      expect(getOutpostPiRuntimeCoordinator().isReplacing()).toBe(false);
      expect(harness.pendingDeliveryCount()).toBe(0);
      expect(harness.deliveries.filter((delivery) => delivery.content === "expire without successor")).toHaveLength(0);
    } finally {
      restoreTtl();
    }
  });

  test("a replacement-gap message reports pending and drains exactly once to the successor", async () => {
    const harness = await createProductionHarness();
    const sessionId = harness.currentRemoteSessionId();
    const paused = await harness.beginPausedNewSession();
    const channel = harness.routeCurrent(userMessage("gap-message", sessionId, "during replacement"));

    await channel.waitForMessage(deliveryPendingFor("gap-message"));
    expect(internalErrorFor(channel, "gap-message")).toBe(false);
    expect(harness.pendingDeliveryCount()).toBe(1);

    await paused.complete();
    await harness.waitForDelivery((delivery) =>
      delivery.sessionLabel === "replacement-2"
      && delivery.method === "sendUserMessage"
      && delivery.content === "during replacement",
    );
    expect(harness.deliveries.filter((delivery) => delivery.content === "during replacement")).toHaveLength(1);
    expect(harness.pendingDeliveryCount()).toBe(0);
    expect(internalErrorFor(channel, "gap-message")).toBe(false);
  });

  test("duplicate session_start(new) cannot double-drain the production queue", async () => {
    const harness = await createProductionHarness();
    const sessionId = harness.currentRemoteSessionId();
    const paused = await harness.beginPausedNewSession();
    const channel = harness.routeCurrent(userMessage("duplicate-start", sessionId, "deliver once"));

    await channel.waitForMessage(deliveryPendingFor("duplicate-start"));
    await paused.complete();
    await harness.currentRunner.emit({ type: "session_start", reason: "new" });
    await harness.waitForDelivery((delivery) => delivery.content === "deliver once");

    expect(harness.deliveries.filter((delivery) => delivery.content === "deliver once")).toHaveLength(1);
    expect(harness.pendingDeliveryCount()).toBe(0);
    expect(internalErrorFor(channel, "duplicate-start")).toBe(false);
  });

  test("stale predecessor teardown cannot clear or fail a queued production message", async () => {
    const harness = await createProductionHarness();
    const firstReplacement = await harness.beginPausedNewSession();
    const stalePredecessor = firstReplacement.predecessor;
    await firstReplacement.complete();

    const currentSessionId = harness.currentRemoteSessionId();
    const secondReplacement = await harness.beginPausedNewSession();
    const channel = harness.routeCurrent(userMessage("teardown-sentinel", currentSessionId, "survive stale quit"));
    await channel.waitForMessage(deliveryPendingFor("teardown-sentinel"));
    expect(harness.pendingDeliveryCount()).toBe(1);

    await harness.emitStaleShutdown(stalePredecessor, "quit");
    expect(harness.pendingDeliveryCount()).toBe(1);
    expect(internalErrorFor(channel, "teardown-sentinel")).toBe(false);

    await secondReplacement.complete();
    await harness.waitForDelivery((delivery) =>
      delivery.sessionLabel === "replacement-3"
      && delivery.method === "sendUserMessage"
      && delivery.content === "survive stale quit",
    );
    expect(harness.deliveries.filter((delivery) => delivery.content === "survive stale quit")).toHaveLength(1);
    expect(harness.pendingDeliveryCount()).toBe(0);
    expect(internalErrorFor(channel, "teardown-sentinel")).toBe(false);
  });
});

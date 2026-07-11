import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { describe, expect, test } from "vitest";
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
import { createRemotePiExtensionRuntime, type RemotePiRuntime } from "../extension/composition_root.js";
import type { RemotePiRuntimePorts } from "../extension/ports.js";
import { RemotePiRuntimeCoordinator } from "../extension/runtime_coordinator.js";

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
  runtime: RemotePiRuntime;
  runner: ExtensionRunner;
  sessionId: string;
}

class RealSdkHarness {
  readonly coordinator = new RemotePiRuntimeCoordinator();
  readonly eventBus = createEventBus();
  readonly deliveries: Array<{ label: string; content: unknown }> = [];
  readonly queued: unknown[] = [];
  clears = 0;
  relayStops = 0;
  meshCloses = 0;
  private boundApi: ExtensionAPI | null = null;
  private bindingLabel = "";

  async create(label: string): Promise<Instance> {
    const cwd = mkdtempSync(join(tmpdir(), `remote-pi-${label}-`));
    const sessionManager = SessionManager.create(cwd, join(cwd, "sessions"));
    const sdkRuntime = createExtensionRuntime();
    let api!: ExtensionAPI;
    let remoteRuntime!: RemotePiRuntime;
    const factory: ExtensionFactory = (factoryApi) => {
      api = factoryApi;
      remoteRuntime = createRemotePiExtensionRuntime(
        factoryApi,
        this.ports(label),
        this.coordinator,
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

  private ports(label: string): RemotePiRuntimePorts {
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

describe("RemotePiRuntimeCoordinator with the real Pi SDK factory/runtime", () => {
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
    expect(h.coordinator.snapshot()).toMatchObject({ kind: "ACTIVE", sessionId: parent.sessionId, childCount: 0 });
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
    expect(h.coordinator.snapshot()).toMatchObject({ kind: "ACTIVE", sessionId: parent.sessionId });
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

import type { ExtensionAPI, ExtensionContext, ExtensionFactory } from "@earendil-works/pi-coding-agent";
import type { RemotePiRuntimePorts, RuntimeEpoch } from "./ports.js";
import {
  getRemotePiRuntimeCoordinator,
  type FactoryLease,
  type RemotePiRuntimeCoordinator,
  type SessionLifecycleReason,
} from "./runtime_coordinator.js";

let nextEpochId = 1;

export interface RemotePiRuntime {
  readonly epoch: RuntimeEpoch;
  readonly ports: RemotePiRuntimePorts;
  readonly lease: FactoryLease;
  register(): void;
  registerLifecycle(): void;
  isOwner(): boolean;
  dispose(): Promise<void>;
}

export function createRuntimeEpoch(): RuntimeEpoch {
  let disposed = false;
  const id = nextEpochId++;
  return {
    id,
    get disposed() {
      return disposed;
    },
    isCurrent() {
      return !disposed;
    },
    dispose() {
      disposed = true;
    },
  };
}

export function createRemotePiExtensionRuntime(
  pi: ExtensionAPI,
  ports: RemotePiRuntimePorts,
  coordinator: RemotePiRuntimeCoordinator = getRemotePiRuntimeCoordinator(),
): RemotePiRuntime {
  const epoch = createRuntimeEpoch();
  const lease = coordinator.acquireFactory();
  const eventBus = (pi as Partial<ExtensionAPI>).events;
  const hasEventBus = !!eventBus && typeof eventBus === "object" && typeof eventBus.on === "function";
  if (hasEventBus) coordinator.observeChildLifecycle(eventBus);
  // Legacy broad unit fixtures predate session_start-driven ownership and
  // intentionally exercise handlers in isolation. They opt into an explicit
  // test seam; production ExtensionAPI objects always carry a real event bus.
  // Real lifecycle behavior is covered against the installed SDK integration.
  const isolatedTestHarness = (pi as ExtensionAPI & { __remotePiTestHarness?: boolean }).__remotePiTestHarness === true
    || !hasEventBus;
  if (isolatedTestHarness) {
    coordinator.activate(lease, "test-harness", pi);
    ports.session.bindApi(pi);
  }
  const runtime: RemotePiRuntime = {
    epoch,
    ports,
    lease,
    register() {
      runtime.registerLifecycle();
      ports.commands.register(pi, runtime);
    },
    registerLifecycle() {
      registerLifecycleHooks(pi, ports, epoch, coordinator, lease);
    },
    isOwner() {
      return isolatedTestHarness || coordinator.isOwner(lease);
    },
    async dispose() {
      if (!coordinator.beginShutdown(lease, "quit")) return;
      await disposeRuntimePorts(ports, epoch, "quit");
    },
  };
  return runtime;
}

export function registerLifecycleHooks(
  pi: ExtensionAPI,
  ports: RemotePiRuntimePorts,
  epoch: RuntimeEpoch,
  coordinator: RemotePiRuntimeCoordinator,
  lease: FactoryLease,
): void {
  pi.on("session_start", (_event: unknown, ctx: ExtensionContext) => {
    const reason = sessionReason(_event, "startup");
    const sessionId = sessionIdFrom(ctx);
    const activation = coordinator.activate(lease, sessionId, pi);
    if (activation.status !== "activated") return;

    // Publish the factory-local API only after the ownership claim succeeds.
    // bindApi drains process-scoped pending ingress after the fresh API is live.
    ports.session.bindApi(pi);
    ports.session.bindSessionContext(ctx);
    ports.session.onSessionLifecycle?.(reason, tail(sessionId));
    if (!epoch.isCurrent()) return;
    void ports.commands.ensureStarted?.(ctx);
  });

  pi.on("session_shutdown", async (_event?: unknown) => {
    const reason = sessionReason(_event, "quit");
    if (!coordinator.beginShutdown(lease, reason)) return;
    ports.session.onSessionLifecycle?.(reason, "");
    await disposeRuntimePorts(ports, epoch, reason);
  });
}

async function disposeRuntimePorts(
  ports: RemotePiRuntimePorts,
  epoch: RuntimeEpoch,
  reason: SessionLifecycleReason,
): Promise<void> {
  epoch.dispose();
  ports.commands.prepareSessionShutdown?.();
  ports.session.clearStaleContexts(reason);
  ports.relay.detachCrossPcBridge();
  ports.relay.stop();
  await ports.commands.closeMesh?.();
}

export function createRemotePiExtensionFactory(
  createPorts: () => RemotePiRuntimePorts,
): ExtensionFactory {
  return (pi: ExtensionAPI) => {
    const runtime = createRemotePiExtensionRuntime(pi, createPorts());
    runtime.register();
  };
}

function isSessionEvent(event: unknown): event is { reason?: string } {
  return typeof event === "object" && event !== null && "reason" in event
    && typeof (event as { reason?: unknown }).reason === "string";
}

function sessionReason(event: unknown, fallback: SessionLifecycleReason): SessionLifecycleReason {
  const reason = isSessionEvent(event) ? event.reason : undefined;
  return reason === "startup" || reason === "reload" || reason === "new" || reason === "resume"
      || reason === "fork" || reason === "quit"
    ? reason
    : fallback;
}

function sessionIdFrom(ctx: ExtensionContext): string {
  const sm = (ctx as { sessionManager?: { getSessionId?: () => string } }).sessionManager;
  const id = sm?.getSessionId?.();
  // A real SDK session_start always has an id. Keep a stable per-context
  // fallback for narrow test harnesses rather than merging unrelated starts.
  return id && id.length > 0 ? id : `context:${contextIdentity(ctx)}`;
}

const contextIds = new WeakMap<object, number>();
let nextContextId = 1;
function contextIdentity(ctx: object): number {
  const existing = contextIds.get(ctx);
  if (existing) return existing;
  const id = nextContextId++;
  contextIds.set(ctx, id);
  return id;
}

function tail(id: string): string {
  return id.length <= 8 ? id : id.slice(-8);
}

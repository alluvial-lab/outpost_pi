import type { ExtensionAPI, ExtensionContext, ExtensionFactory } from "@earendil-works/pi-coding-agent";
import { BackgroundActivityTracker } from "./background_activity.js";
import type { OutpostPiRuntime, OutpostPiRuntimePorts, RuntimeEpoch } from "./ports.js";
import {
  getOutpostPiRuntimeCoordinator,
  type FactoryLease,
  type OutpostPiRuntimeCoordinator,
  type SessionLifecycleReason,
} from "./runtime_coordinator.js";

let nextEpochId = 1;

/** Create an independently disposable epoch that guards stale asynchronous runtime work. */
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

/** Compose a lifecycle-owned extension runtime from injected ports and coordinator authority. */
export function createOutpostPiExtensionRuntime(
  pi: ExtensionAPI,
  ports: OutpostPiRuntimePorts,
  coordinator: OutpostPiRuntimeCoordinator = getOutpostPiRuntimeCoordinator(),
  backgroundActivityTracker?: BackgroundActivityTracker,
): OutpostPiRuntime {
  const epoch = createRuntimeEpoch();
  const lease = coordinator.acquireFactory();
  const tracker = backgroundActivityTracker ?? new BackgroundActivityTracker(({ activeCount }) => {
    ports.relay.sendRoomMeta({ background: activeCount > 0 });
  });
  const ownsTracker = backgroundActivityTracker === undefined;
  const eventBus = (pi as Partial<ExtensionAPI>).events;
  const hasEventBus = !!eventBus && typeof eventBus === "object" && typeof eventBus.on === "function";
  if (hasEventBus) {
    coordinator.observeChildLifecycle(eventBus);
    tracker.subscribe(eventBus);
  }
  // Legacy broad unit fixtures predate session_start-driven ownership and
  // intentionally exercise handlers in isolation. They opt into an explicit
  // test seam; production ExtensionAPI objects always carry a real event bus.
  // Real lifecycle behavior is covered against the installed SDK integration.
  const isolatedTestHarness = (pi as ExtensionAPI & { __outpostPiTestHarness?: boolean }).__outpostPiTestHarness === true
    || !hasEventBus;
  if (isolatedTestHarness) {
    coordinator.activate(lease, "test-harness", pi);
    ports.session.bindApi(pi);
  }
  const runtime: OutpostPiRuntime = {
    epoch,
    ports,
    lease,
    register() {
      runtime.registerLifecycle();
      ports.commands.register(pi, runtime);
    },
    registerLifecycle() {
      registerLifecycleHooks(pi, ports, epoch, coordinator, lease, runtime, tracker, ownsTracker);
    },
    isOwner() {
      return isolatedTestHarness || coordinator.isOwner(lease);
    },
    async dispose(reason: SessionLifecycleReason = "quit") {
      if (!coordinator.beginShutdown(lease, reason)) return false;
      ports.session.onSessionLifecycle?.(reason, "");
      await disposeRuntimePorts(ports, epoch, reason, tracker, ownsTracker);
      return true;
    },
  };
  return runtime;
}

/** Bind Pi session hooks that acquire ownership, refresh session context, and tear down runtime ports. */
export function registerLifecycleHooks(
  pi: ExtensionAPI,
  ports: OutpostPiRuntimePorts,
  epoch: RuntimeEpoch,
  coordinator: OutpostPiRuntimeCoordinator,
  lease: FactoryLease,
  runtime: OutpostPiRuntime,
  tracker: BackgroundActivityTracker,
  ownsTracker: boolean,
): void {
  pi.on("session_start", (_event: unknown, ctx: ExtensionContext) => {
    const reason = sessionReason(_event, "startup");
    const sessionId = sessionIdFrom(ctx);
    const activation = coordinator.activate(lease, sessionId, pi);
    if (activation.status !== "activated") return;

    ports.commands.activateRuntime?.(runtime);
    // Publish the factory-local API only after the ownership claim succeeds.
    // bindApi drains process-scoped pending ingress after the fresh API is live.
    ports.session.bindApi(pi);
    ports.session.bindSessionContext(ctx);
    ports.session.onSessionLifecycle?.(reason, tail(sessionId));
    if (!epoch.isCurrent()) return;

    // Runtime identity is written only after this epoch wins ownership. The
    // optional capability keeps the filesystem adapter out of this composition
    // root's lifecycle policy while allowing the extension to publish a
    // process-scoped identity for shell-based hot-reload arming.
    const sessionStart = ports.session as typeof ports.session & { onSessionStart?: () => void };
    sessionStart.onSessionStart?.();

    // A new session is genuinely idle. Force-publish working=false to clear a
    // stale working=true left in the relay's room state by a killed
    // predecessor (an ungraceful SIGKILL during an active turn skips
    // session_shutdown, so resetTurnSnapshot never converges). resetTurnSnapshot is a no-op when
    // the projection is already idle (false→false publishes nothing), so an
    // explicit publishWorking(false) is required. Safe to no-op if the relay
    // is not connected yet (sendControl is optional-chained); the first real
    // turn's working=true will publish on the live connection.
    ports.session.publishWorking(false);

    // Print mode is a one-shot invocation. Starting the relay here retains a
    // WebSocket handle after the answer is printed and prevents process exit.
    // Prefer the SDK mode, with argv as a compatibility guard for older Pi
    // contexts that did not expose it.
    const printMode = ctx.mode === "print"
      || process.argv.includes("-p")
      || process.argv.includes("--print");
    if (!printMode) ports.commands.ensureStarted?.(ctx);
  });

  pi.on("session_shutdown", async (_event?: unknown) => {
    const reason = sessionReason(_event, "quit");
    if (!coordinator.beginShutdown(lease, reason)) return;
    ports.session.onSessionLifecycle?.(reason, "");
    await disposeRuntimePorts(ports, epoch, reason, tracker, ownsTracker);
  });
}

async function disposeRuntimePorts(
  ports: OutpostPiRuntimePorts,
  epoch: RuntimeEpoch,
  reason: SessionLifecycleReason,
  tracker: BackgroundActivityTracker,
  ownsTracker: boolean,
): Promise<void> {
  epoch.dispose();
  ports.commands.prepareSessionShutdown?.();
  // A provided tracker belongs to the process-scoped extension composition;
  // an internally-created tracker belongs to this runtime and can be stopped
  // with it. Both paths converge the background projection before relay stop.
  tracker.clearForSessionBoundary();
  if (ownsTracker) tracker.dispose();
  // Converge the turn projection and publish working=false BEFORE the relay
  // stops — a session_shutdown during an active turn invalidates the old
  // runner, so terminal agent_end/turn_end events are dropped and the
  // reducer-owned working=true would never publish. resetTurnSnapshot crosses
  // the true→false edge (publishing via the diff) and leaves the projection
  // idle for the successor. Must run while the relay is still connected.
  ports.session.resetTurnSnapshot();
  ports.session.clearStaleContexts(reason);
  ports.relay.detachCrossPcBridge();
  let relayStop: Promise<void>;
  try {
    relayStop = ports.relay.stop();
  } catch (error) {
    relayStop = Promise.reject(error);
  }
  let meshClose: Promise<void>;
  try {
    meshClose = ports.commands.closeMesh?.() ?? Promise.resolve();
  } catch (error) {
    meshClose = Promise.reject(error);
  }
  const [relayResult, meshResult] = await Promise.allSettled([
    relayStop,
    meshClose,
  ]);
  if (relayResult.status === "rejected") throw relayResult.reason;
  if (meshResult.status === "rejected") throw meshResult.reason;
}

/** Create the SDK factory that supplies a fresh port graph for each extension instance. */
export function createOutpostPiExtensionFactory(
  createPorts: () => OutpostPiRuntimePorts,
): ExtensionFactory {
  return (pi: ExtensionAPI) => {
    const runtime = createOutpostPiExtensionRuntime(pi, createPorts());
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

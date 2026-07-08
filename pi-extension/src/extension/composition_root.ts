import type { ExtensionAPI, ExtensionContext, ExtensionFactory } from "@earendil-works/pi-coding-agent";
import type { RemotePiRuntimePorts, RuntimeEpoch } from "./ports.js";

let nextEpochId = 1;

export interface RemotePiRuntime {
  readonly epoch: RuntimeEpoch;
  readonly ports: RemotePiRuntimePorts;
  register(): void;
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
): RemotePiRuntime {
  const epoch = createRuntimeEpoch();
  const runtime: RemotePiRuntime = {
    epoch,
    ports,
    register() {
      ports.session.bindApi(pi);
      registerLifecycleHooks(pi, ports, epoch);
      ports.commands.register(pi, runtime);
    },
    async dispose() {
      await disposeRuntimePorts(ports, epoch);
    },
  };
  return runtime;
}

export function registerLifecycleHooks(
  pi: ExtensionAPI,
  ports: RemotePiRuntimePorts,
  epoch: RuntimeEpoch,
): void {
  pi.on("session_start", (_event: unknown, ctx: ExtensionContext) => {
    ports.session.bindSessionContext(ctx);
    const reason = (isSessionEvent(_event) ? _event.reason : undefined) ?? "startup";
    ports.session.onSessionLifecycle?.(reason, sessionIdTail(ctx));
    if (!epoch.isCurrent()) return;
    void ports.commands.ensureStarted?.(ctx);
  });

  pi.on("session_shutdown", async (_event?: unknown) => {
    const reason = (isSessionEvent(_event) ? _event.reason : undefined) ?? "quit";
    ports.session.onSessionLifecycle?.(reason, "");
    await disposeRuntimePorts(ports, epoch);
  });
}

async function disposeRuntimePorts(
  ports: RemotePiRuntimePorts,
  epoch: RuntimeEpoch,
): Promise<void> {
  epoch.dispose();
  ports.commands.prepareSessionShutdown?.();
  ports.session.clearStaleContexts();
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

// ── Delivery-path debug helpers ─────────────────────────────────────────────

/** Narrow an unknown SDK session event to its `reason` field. The SDK's
 *  `SessionStartEvent`/`SessionShutdownEvent` carry `reason`; the event is
 *  typed `unknown` here because the SDK type isn't imported at this layer. */
function isSessionEvent(event: unknown): event is { reason?: string } {
  return typeof event === "object" && event !== null && "reason" in event
    && typeof (event as { reason?: unknown }).reason === "string";
}

/** Tail of the session id from a session ctx (for correlation; matches the
 *  relay's `id_tail` convention). Empty when no session id is resolvable. */
function sessionIdTail(ctx: ExtensionContext): string {
  const sm = (ctx as { sessionManager?: { getSessionId?: () => string } }).sessionManager;
  const id = sm?.getSessionId?.();
  return id ? (id.length <= 8 ? id : id.slice(-8)) : "";
}

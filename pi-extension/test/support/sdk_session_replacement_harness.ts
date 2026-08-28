import {
  AgentSessionRuntime,
  createEventBus,
  createExtensionRuntime,
  ExtensionRunner,
  SessionManager,
  type Extension,
  type ExtensionActions,
  type EventBus,
  type ExtensionCommandContext,
  type ExtensionCommandContextActions,
  type ExtensionContextActions,
  type ExtensionFactory,
  type ExtensionRuntime,
  type ReplacedSessionContext,
  type SessionShutdownEvent,
  type SessionStartEvent,
} from "@earendil-works/pi-coding-agent";
import { vi } from "vitest";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import type { ClientMessage, ServerMessage } from "../../src/protocol/types.js";
import { resetOutpostPiRuntimeCoordinatorForTest } from "../../src/extension/runtime_coordinator.js";

type LoadExtensionFromFactory = (
  factory: ExtensionFactory,
  cwd: string,
  eventBus: EventBus,
  runtime: ExtensionRuntime,
  extensionPath?: string,
) => Promise<Extension>;

/** Load through Pi's installed runtime so the harness exercises real API guards and listener ownership. */
async function realSdkFactoryLoader(): Promise<LoadExtensionFromFactory> {
  const packageEntry = fileURLToPath(import.meta.resolve("@earendil-works/pi-coding-agent"));
  const loaderUrl = pathToFileURL(join(dirname(packageEntry), "core/extensions/loader.js")).href;
  const module = await import(loaderUrl) as { loadExtensionFromFactory?: LoadExtensionFromFactory };
  if (typeof module.loadExtensionFromFactory !== "function") {
    throw new Error("installed Pi SDK does not expose its factory loader implementation");
  }
  return module.loadExtensionFromFactory;
}

type OutpostPiIndexModule = {
  default: ExtensionFactory;
  _routeClientMessageFrom: (
    sender: { send(msg: ServerMessage): void },
    msg: ClientMessage,
    ctx: Pick<ExtensionCommandContext, "abort">,
  ) => void;
  _getRemoteSessionIdForTest: () => string | null;
  _getPendingDeliveryQueueLengthForTest: () => number;
  _resetPendingDeliveryQueueForTest: () => void;
  _setPendingDeliveryTtlForTest: (ms: number) => () => void;
  _setPendingDeliveryAbsoluteDeadlineForTest: (ms: number) => () => void;
  _setPiForTest: (pi: unknown) => void;
  _setDisposedForTest?: (value: boolean) => void;
  _resetCwdLockForTest?: () => void;
};

export type Delivery = {
  sessionLabel: string;
  method: "sendUserMessage" | "sendMessage";
  content: unknown;
};

export type CompactCall = {
  sessionLabel: string;
  options: unknown;
};

export type LifecycleEvent =
  | { type: "session_start"; reason: SessionStartEvent["reason"]; sessionId: string }
  | { type: "session_shutdown"; reason: SessionShutdownEvent["reason"]; sessionId: string };

export type NewSessionCall = {
  sessionLabel: string;
  hasWithSession: boolean;
};

export class TestPeerChannel {
  readonly sent: ServerMessage[] = [];
  private readonly waiters: Array<{
    predicate: (msg: ServerMessage) => boolean;
    resolve: (msg: ServerMessage) => void;
    reject: (err: Error) => void;
    timer: NodeJS.Timeout;
  }> = [];

  send(msg: ServerMessage): void {
    this.sent.push(msg);
    for (const waiter of [...this.waiters]) {
      if (!waiter.predicate(msg)) continue;
      clearTimeout(waiter.timer);
      this.waiters.splice(this.waiters.indexOf(waiter), 1);
      waiter.resolve(msg);
    }
  }

  waitForMessage(
    predicate: (msg: ServerMessage) => boolean,
    timeoutMs = 1_000,
  ): Promise<ServerMessage> {
    const existing = this.sent.find(predicate);
    if (existing) return Promise.resolve(existing);
    return new Promise((resolve, reject) => {
      const waiter = {
        predicate,
        resolve,
        reject,
        timer: setTimeout(() => {
          this.waiters.splice(this.waiters.indexOf(waiter), 1);
          reject(new Error("Timed out waiting for peer message"));
        }, timeoutMs),
      };
      this.waiters.push(waiter);
    });
  }

  dispose(): void {
    for (const waiter of this.waiters.splice(0)) {
      clearTimeout(waiter.timer);
      waiter.reject(new Error("Peer channel disposed"));
    }
  }
}

export type HarnessSession = {
  label: string;
  indexModule: OutpostPiIndexModule;
  extension: Extension;
  extensionRunner: ExtensionRunner;
  sessionManager: SessionManager;
  sessionFile: string | undefined;
  agent: { state: { messages: unknown[] } };
  abort(): Promise<void>;
  dispose(): void;
  createReplacedSessionContext(): ReplacedSessionContext;
};

export type SdkSessionReplacementHarnessOptions = {
  cwd: string;
  agentDir?: string;
  sessionManager?: SessionManager;
  sessionStartEvent?: SessionStartEvent;
};

export class SdkSessionReplacementHarness {
  readonly lifecycleEvents: LifecycleEvent[] = [];
  readonly deliveries: Delivery[] = [];
  readonly compactCalls: CompactCall[] = [];
  readonly newSessionCalls: NewSessionCall[] = [];

  private host!: AgentSessionRuntime;
  private sequence = 0;
  private replacementGate: {
    entered: Deferred;
    release: Deferred;
  } | null = null;

  private constructor(
    private readonly cwd: string,
    private readonly agentDir: string,
    private readonly initialSessionManager: SessionManager,
    private readonly initialSessionStartEvent: SessionStartEvent,
  ) {}

  static async create(options: SdkSessionReplacementHarnessOptions): Promise<SdkSessionReplacementHarness> {
    const sessionManager = options.sessionManager ?? SessionManager.inMemory(options.cwd);
    resetOutpostPiRuntimeCoordinatorForTest();
    vi.resetModules();
    const harness = new SdkSessionReplacementHarness(
      options.cwd,
      options.agentDir ?? `${options.cwd}/.pi`,
      sessionManager,
      options.sessionStartEvent ?? { type: "session_start", reason: "startup" },
    );
    await harness.start();
    return harness;
  }

  get runtime(): AgentSessionRuntime {
    return this.host;
  }

  get currentSession(): HarnessSession {
    return this.host.session as unknown as HarnessSession;
  }

  get currentRunner(): ExtensionRunner {
    return this.currentSession.extensionRunner;
  }

  get currentModule(): OutpostPiIndexModule {
    return this.currentSession.indexModule;
  }

  currentRemoteSessionId(): string {
    const sessionId = this.currentModule._getRemoteSessionIdForTest();
    if (!sessionId) throw new Error("Outpost-Pi extension has not captured a session id");
    return sessionId;
  }

  createCommandContext(): ExtensionCommandContext {
    return this.currentRunner.createCommandContext();
  }

  async primeCommandContext(): Promise<ExtensionCommandContext> {
    const ctx = this.createCommandContext();
    const command = this.currentRunner.getCommand("outpost-pi");
    if (!command) throw new Error("Outpost-Pi command was not registered");
    await command.handler("status", ctx);
    return ctx;
  }

  routeFromModule(module: OutpostPiIndexModule, msg: ClientMessage, channel = new TestPeerChannel()): TestPeerChannel {
    // Resolve abort lazily so user-message routing remains available during the
    // intentional gap where the predecessor runner is stale and the successor
    // runner does not exist yet.
    module._routeClientMessageFrom(channel, msg, {
      abort: () => this.currentRunner.createCommandContext().abort(),
    });
    return channel;
  }

  routeCurrent(msg: ClientMessage, channel = new TestPeerChannel()): TestPeerChannel {
    return this.routeFromModule(this.currentModule, msg, channel);
  }

  pendingDeliveryCount(): number {
    return this.currentModule._getPendingDeliveryQueueLengthForTest();
  }

  /**
   * Start a real SDK `/new` replacement and pause after the predecessor has
   * shut down and become stale, but before the successor factory is loaded.
   * This exposes the production replacement gap without replacing the SDK's
   * lifecycle implementation with a test double.
   */
  async beginPausedNewSession(): Promise<{
    predecessor: HarnessSession;
    complete(): Promise<void>;
  }> {
    if (this.replacementGate) throw new Error("a replacement is already paused");
    const predecessor = this.currentSession;
    const gate = { entered: deferred(), release: deferred() };
    this.replacementGate = gate;
    const replacement = this.host.newSession();
    await gate.entered.promise;
    return {
      predecessor,
      complete: async () => {
        gate.release.resolve();
        await replacement;
      },
    };
  }

  /**
   * Invoke a predecessor's actual registered shutdown callback after its SDK
   * runner is stale. ExtensionRunner correctly refuses to emit on an invalid
   * runtime, so this narrow helper calls the retained production callback to
   * verify its lease-token guard and process-global queue effects.
   */
  async emitStaleShutdown(session: HarnessSession, reason: SessionShutdownEvent["reason"]): Promise<void> {
    const handlers = session.extension.handlers.get("session_shutdown") ?? [];
    for (const handler of handlers) {
      await handler({ type: "session_shutdown", reason }, undefined as never);
    }
  }

  waitForDelivery(
    predicate: (delivery: Delivery) => boolean,
    timeoutMs = 1_000,
  ): Promise<Delivery> {
    const existing = this.deliveries.find(predicate);
    if (existing) return Promise.resolve(existing);
    return new Promise((resolve, reject) => {
      const started = Date.now();
      const timer = setInterval(() => {
        const match = this.deliveries.find(predicate);
        if (match) {
          clearInterval(timer);
          resolve(match);
          return;
        }
        if (Date.now() - started >= timeoutMs) {
          clearInterval(timer);
          reject(new Error("Timed out waiting for SDK delivery"));
        }
      }, 5);
    });
  }

  async resumeSession(sessionFile: string): Promise<void> {
    await this.host.switchSession(sessionFile, { withSession: async () => undefined });
  }

  async forkSession(entryId: string): Promise<void> {
    await this.host.fork(entryId, { position: "at", withSession: async () => undefined });
  }

  async dispose(): Promise<void> {
    for (const session of [this.currentSession]) {
      session.indexModule._resetPendingDeliveryQueueForTest();
      session.indexModule._resetCwdLockForTest?.();
    }
    await this.host.dispose();
  }

  private async start(): Promise<void> {
    const initial = await this.createRuntime({
      cwd: this.cwd,
      agentDir: this.agentDir,
      sessionManager: this.initialSessionManager,
      sessionStartEvent: this.initialSessionStartEvent,
    });
    this.host = new AgentSessionRuntime(
      initial.session as never,
      initial.services as never,
      (options) => this.createRuntime(options),
    );
    this.rebind(initial.session as HarnessSession);
    this.host.setBeforeSessionInvalidate(() => {
      // The real Outpost-Pi session_shutdown hook marks the extension disposed.
      // In a headless unit harness there is no relay/mesh process to restart, so
      // reset only that test-exposed auto-start flag before the SDK invalidates
      // the old runner. This keeps the replacement test focused on ctx staleness
      // and prevents a fire-and-forget _cmdRoot from racing cleanup.
      (this.host.session as unknown as HarnessSession).indexModule._setDisposedForTest?.(false);
    });
    this.host.setRebindSession(async (session) => {
      this.rebind(session as unknown as HarnessSession);
    });
  }

  private rebind(session: HarnessSession): void {
    this.bindCommandActions(session.extensionRunner, session.label);
  }

  private async createRuntime(options: {
    cwd: string;
    agentDir: string;
    sessionManager: SessionManager;
    sessionStartEvent?: SessionStartEvent;
  }) {
    if (options.sessionStartEvent && options.sessionStartEvent.reason !== "startup" && this.replacementGate) {
      const gate = this.replacementGate;
      gate.entered.resolve();
      await gate.release.promise;
      this.replacementGate = null;
    }
    this.sequence += 1;
    const label = this.sequence === 1 ? "initial" : `replacement-${this.sequence}`;
    const { extension, runtime, indexModule } = await this.loadOutpostPiExtension(label, options.cwd);
    const runner = new ExtensionRunner(
      [extension, this.makeProbeExtension()],
      runtime,
      options.cwd,
      options.sessionManager,
      {} as never,
    );
    runner.bindCore(
      this.makeActions(label, options.sessionManager),
      this.makeContextActions(label, options.cwd),
    );
    this.bindCommandActions(runner, label);
    const session = this.makeFakeSession(label, extension, runner, options.sessionManager, indexModule);
    if (options.sessionStartEvent) await runner.emit(options.sessionStartEvent);
    return {
      session,
      services: { cwd: options.cwd, agentDir: options.agentDir },
      diagnostics: [],
    };
  }

  private async loadOutpostPiExtension(label: string, cwd: string): Promise<{
    extension: Extension;
    runtime: ExtensionRuntime;
    indexModule: OutpostPiIndexModule;
  }> {
    const runtime = createExtensionRuntime();
    const eventBus = createEventBus();
    const module = await import("../../src/index.js") as OutpostPiIndexModule;
    const load = await realSdkFactoryLoader();
    const extension = await load(
      module.default,
      cwd,
      eventBus,
      runtime,
      `<outpost-pi-session-harness:${label}>`,
    );
    return { extension, runtime, indexModule: module };
  }

  private makeProbeExtension(): Extension {
    const handlers = new Map<string, Array<(event: unknown, ctx: unknown) => Promise<void>>>([
      [
        "session_start",
        [async (event, ctx) => {
          const typedEvent = event as SessionStartEvent;
          const typedCtx = ctx as { sessionManager: { getSessionId(): string } };
          this.lifecycleEvents.push({
            type: "session_start",
            reason: typedEvent.reason,
            sessionId: typedCtx.sessionManager.getSessionId(),
          });
        }],
      ],
      [
        "session_shutdown",
        [async (event, ctx) => {
          const typedEvent = event as SessionShutdownEvent;
          const typedCtx = ctx as { sessionManager: { getSessionId(): string } };
          this.lifecycleEvents.push({
            type: "session_shutdown",
            reason: typedEvent.reason,
            sessionId: typedCtx.sessionManager.getSessionId(),
          });
        }],
      ],
    ]);

    return {
      path: "<session-replacement-probe>",
      resolvedPath: "<session-replacement-probe>",
      sourceInfo: { path: "<session-replacement-probe>" } as never,
      handlers,
      tools: new Map(),
      messageRenderers: new Map(),
      commands: new Map(),
      flags: new Map(),
      shortcuts: new Map(),
    } as unknown as Extension;
  }

  private makeActions(label: string, sessionManager: SessionManager): ExtensionActions {
    return {
      sendMessage: vi.fn((content: unknown) => {
        this.deliveries.push({ sessionLabel: label, method: "sendMessage", content });
      }),
      sendUserMessage: vi.fn((content: unknown) => {
        this.deliveries.push({ sessionLabel: label, method: "sendUserMessage", content });
      }),
      appendEntry: vi.fn((customType: string, data?: unknown) => {
        sessionManager.appendCustomEntry(customType, data);
      }),
      setSessionName: vi.fn(),
      getSessionName: vi.fn(() => undefined),
      setLabel: vi.fn(),
      getActiveTools: vi.fn(() => []),
      getAllTools: vi.fn(() => []),
      setActiveTools: vi.fn(),
      refreshTools: vi.fn(),
      getCommands: vi.fn(() => []),
      setModel: vi.fn(async () => true),
      getThinkingLevel: vi.fn(() => "medium" as never),
      setThinkingLevel: vi.fn(),
    };
  }

  private makeContextActions(label: string, cwd: string): ExtensionContextActions {
    return {
      getModel: () => undefined,
      getScopedModels: () => [],
      isIdle: () => true,
      isProjectTrusted: () => true,
      getSignal: () => undefined,
      abort: vi.fn(),
      hasPendingMessages: () => false,
      shutdown: vi.fn(),
      getContextUsage: () => undefined,
      compact: vi.fn((options?: unknown) => {
        this.compactCalls.push({ sessionLabel: label, options });
      }),
      getSystemPrompt: () => "",
      getSystemPromptOptions: () => ({ cwd }),
    };
  }

  private bindCommandActions(runner: ExtensionRunner, label: string): void {
    const notUsed = async () => ({ cancelled: false });
    runner.bindCommandContext({
      waitForIdle: async () => undefined,
      newSession: async (options) => {
        this.newSessionCalls.push({ sessionLabel: label, hasWithSession: typeof options?.withSession === "function" });
        return this.host ? this.host.newSession(options) : { cancelled: false };
      },
      fork: async (entryId, options) => this.host
        ? this.host.fork(entryId, options)
        : { cancelled: false },
      navigateTree: async () => ({ cancelled: false }),
      switchSession: notUsed,
      reload: async () => runner.invalidate(),
    });
  }

  private makeFakeSession(
    label: string,
    extension: Extension,
    runner: ExtensionRunner,
    sessionManager: SessionManager,
    indexModule: OutpostPiIndexModule,
  ): HarnessSession {
    return {
      label,
      indexModule,
      extension,
      extensionRunner: runner,
      sessionManager,
      sessionFile: sessionManager.getSessionFile(),
      agent: { state: { messages: sessionManager.buildSessionContext().messages } },
      // Pi 0.84 settles an active outgoing turn before replacement teardown.
      // This harness has no agent loop, so there is nothing to abort or persist.
      abort: async () => undefined,
      dispose: () => {
        // This is the real SDK stale-ctx invalidation path: runner.invalidate()
        // installs the stale message consumed by ExtensionRunner.assertActive(),
        // which guarded ctx getters/methods call lazily after replacement.
        runner.invalidate();
      },
      createReplacedSessionContext: () => {
        const context = Object.defineProperties(
          {},
          Object.getOwnPropertyDescriptors(runner.createCommandContext()),
        ) as ReplacedSessionContext;
        context.sendUserMessage = async (content: unknown) => {
          this.deliveries.push({ sessionLabel: label, method: "sendUserMessage", content });
        };
        context.sendMessage = async (message: unknown) => {
          this.deliveries.push({ sessionLabel: label, method: "sendMessage", content: message });
        };
        return context;
      },
    };
  }
}

type Deferred = {
  promise: Promise<void>;
  resolve(): void;
};

function deferred(): Deferred {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => { resolve = done; });
  return { promise, resolve };
}

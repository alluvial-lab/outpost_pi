import { mkdirSync, rmSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import {
  createEventBus,
  createExtensionRuntime,
  ExtensionRunner,
  SessionManager,
  type EventBus,
  type Extension,
  type ExtensionActions,
  type ExtensionCommandContextActions,
  type ExtensionContextActions,
  type ExtensionFactory,
  type ExtensionRuntime,
  type ModelRegistry,
} from "@earendil-works/pi-coding-agent";
import { roomIdFor } from "../../src/rooms.js";
import { defaultAgentName } from "../../src/session/local_config.js";

export interface PiHostStatus {
  readonly generation: string;
  readonly state: "idle" | "started" | "paired";
  readonly sessionId: string;
  readonly roomId: string;
  readonly relayConnected: boolean;
  readonly meshAddress: string | null;
  readonly sessionContextHasMessageActions: boolean;
}

export interface PiHostTuiEvent {
  readonly seq: number;
  readonly kind: "tui_message" | "notification";
  readonly payload: unknown;
}

export interface PiHostTurnControlStatus {
  readonly phase: "idle" | "armed" | "pending" | "settled";
}

export interface PiHostDeliveryControlStatus {
  readonly fenced: boolean;
  readonly sdkDeliveryCount: number;
}

/** Lifecycle edge names accepted by the background-work E2E seam. */
export type BackgroundLifecycleEvent =
  | "created"
  | "completed"
  | "failed"
  | "resumed";

type ProductionModule = {
  default: ExtensionFactory;
  outpostPiTestHarness: {
    connect(ctx: unknown): Promise<void>;
    state(): "idle" | "started" | "paired";
    /** The room this Pi actually registered with the relay; null while idle. */
    roomId(): string | null;
    /** The effective name used to derive that room. */
    name(): string | null;
    meshAddress(): string | null;
    meshBridgeActive(): boolean;
    meshPeers(): Promise<string[]>;
    meshTarget(pcPubkey: string, remoteAddress: string): string | null;
    sendDirectMeshMessage(input: {
      toPc: string;
      toRoom: string;
      toAddress: string;
      body: unknown;
    }): boolean;
    refreshMeshMembership(): Promise<void>;
  };
  _getLockedNameForTest(): string | null;
  _getOwnerDeliveryFenceReasonForTest():
    | "hot_reload"
    | "fresh_session"
    | null;
  _drainOwnerChannelsForTest(): Promise<void>;
  _setHotReloadingForTest(value: boolean): void;
  _resetCwdLockForTest(): void;
  _startRelayForTest(ctx: unknown): Promise<void>;
};

type LoadExtensionFromFactory = (
  factory: ExtensionFactory,
  cwd: string,
  eventBus: EventBus,
  runtime: ExtensionRuntime,
  extensionPath?: string,
) => Promise<Extension>;

/**
 * Run the production extension factory inside the installed Pi SDK runner.
 *
 * The HTTP service owns this runtime for one process generation. Process exit
 * is the reset boundary, matching the production extension's process-global
 * coordinator, QR token, identity, and owner-channel lifecycle.
 */
export class E2ePiHostRuntime {
  readonly generation = crypto.randomUUID();
  private readonly events: PiHostTuiEvent[] = [];
  private seq = 0;
  private disposed = false;
  private turnControlPhase: PiHostTurnControlStatus["phase"] = "idle";
  private stagedReply: string | null = null;
  private deferredTurnResolve: (() => void) | null = null;
  private sdkDeliveryCount = 0;
  private readonly sessions = new Map<string, SessionManager>();

  private constructor(
    private readonly cwd: string,
    private sessionManager: SessionManager,
    private readonly runner: ExtensionRunner,
    private readonly eventBus: EventBus,
    private readonly production: ProductionModule,
    private readonly sessionContextHasMessageActions: boolean,
  ) {
    this.sessions.set(sessionManager.getSessionId(), sessionManager);
  }

  static async start(options: {
    relayUrl: string;
    cwd: string;
    seededTranscriptText: string;
    preserveState?: boolean;
    freshSession?: boolean;
    agentName?: string;
  }): Promise<E2ePiHostRuntime> {
    process.env.OUTPOST_PI_RELAY = options.relayUrl;
    process.env.OUTPOST_PI_DIRECT_CONFIG = JSON.stringify({
      agent_name: options.agentName ?? defaultAgentName(options.cwd),
      auto_start_relay: false,
    });
    process.env.OUTPOST_PI_ALLOW_FILE_IDENTITY = "1";

    // HOME is fixed by Compose before Node starts, so modules that resolve
    // homedir() at import time see this isolated path. Ordinary test-isolation
    // restarts clear all state; the live device lane can instead preserve the
    // machine identity and owner channel to model a production process restart.
    if (!options.preserveState) {
      rmSync(homedir(), { recursive: true, force: true });
      rmSync(options.cwd, { recursive: true, force: true });
    }
    // The headless pair-code seam lives outside HOME and the extension refuses
    // to overwrite a pre-existing target (symlink-attack hardening), so a stale
    // file from an earlier generation would 500 every later `pair` command.
    const pairCodeFile = process.env.OUTPOST_PI_PAIR_CODE_FILE;
    if (pairCodeFile) rmSync(pairCodeFile, { force: true });
    mkdirSync(homedir(), { recursive: true, mode: 0o700 });
    mkdirSync(options.cwd, { recursive: true });

    const sessionDir = join(homedir(), ".pi", "e2e-sessions");
    const sessionManager = options.preserveState && !options.freshSession
      ? SessionManager.continueRecent(options.cwd, sessionDir)
      : SessionManager.create(options.cwd, sessionDir);
    if (!options.preserveState) {
      sessionManager.appendMessage({
        role: "user",
        content: options.seededTranscriptText,
      } as never);
    }

    const sdkRuntime = createExtensionRuntime();
    const eventBus = createEventBus();
    const production = await import("../../src/index.js") as ProductionModule;
    const load = await realSdkFactoryLoader();
    const extension = await load(
      production.default,
      options.cwd,
      eventBus,
      sdkRuntime,
      "<outpost-pi-e2e-host>",
    );
    const runner = new ExtensionRunner(
      [extension],
      sdkRuntime,
      options.cwd,
      sessionManager,
      {} as ModelRegistry,
    );

    let instance!: E2ePiHostRuntime;
    runner.bindCore(actions(
      sessionManager,
      (kind, payload) => instance.record(kind, payload),
      (content) => instance.handleSendUserMessage(content),
    ), contextActions(options.cwd));
    runner.bindCommandContext({
      waitForIdle: async () => undefined,
      newSession: async (newSessionOptions) => instance.replaceSession(newSessionOptions),
      fork: async () => ({ cancelled: false }),
      navigateTree: async () => ({ cancelled: false }),
      switchSession: async () => ({ cancelled: false }),
      reload: async () => undefined,
    });
    runner.setUIContext(ui((kind, payload) => instance.record(kind, payload)) as never, "rpc");

    const sessionContext = runner.createContext() as unknown as Record<string, unknown>;
    instance = new E2ePiHostRuntime(
      options.cwd,
      sessionManager,
      runner,
      eventBus,
      production,
      typeof sessionContext.sendMessage === "function"
        || typeof sessionContext.sendUserMessage === "function",
    );
    await runner.emit({ type: "session_start", reason: "startup" });
    if (process.env.E2E_PI_MESH_ENABLED === "1") {
      // The mesh lane deliberately uses the production connect path: local UDS
      // broker, relay bridge, membership discovery, and owner channel all stay
      // real. Other live lanes retain relay-only startup and its stable room.
      await production.outpostPiTestHarness.connect(runner.createContext());
    } else {
      await production._startRelayForTest(runner.createContext());
    }
    return instance;
  }

  status(): PiHostStatus {
    const state = this.production.outpostPiTestHarness.state();
    return {
      generation: this.generation,
      state,
      sessionId: this.sessionManager.getSessionId(),
      // Read the room the production extension ACTUALLY registered with the
      // relay — do NOT re-derive it. The registered room is derived from the
      // mesh-assigned agent name, which may carry a broker collision suffix
      // (e.g. `e2e-agent#2`) that a `(cwd, "e2e-agent")` re-derivation cannot
      // reconstruct. Re-deriving here diverged from the QR/pair-code room and
      // turned every `*.roomId == status.roomId` e2e assertion red whenever a
      // collision occurred. The idle fallback is the no-mesh derivation (config
      // agent name, no suffix possible) and is never the asserted state.
      roomId: this.production.outpostPiTestHarness.roomId()
        ?? roomIdFor(this.cwd, defaultAgentName(this.cwd)),
      relayConnected: state !== "idle",
      meshAddress: this.production.outpostPiTestHarness.meshAddress(),
      sessionContextHasMessageActions: this.sessionContextHasMessageActions,
    };
  }

  async invokeOutpostPi(args: string): Promise<void> {
    if (this.disposed) throw new Error("Pi host runtime is disposed");
    const command = this.runner.getCommand("outpost-pi");
    if (!command) throw new Error("production /outpost-pi command was not registered");
    await command.handler(args, this.runner.createCommandContext());
  }

  eventsAfter(seq: number): readonly PiHostTuiEvent[] {
    return this.events.filter((event) => event.seq > seq);
  }

  /** Refresh signed membership and return the production broker's current roster. */
  async refreshMeshMembership(): Promise<readonly string[]> {
    await this.production.outpostPiTestHarness.refreshMeshMembership();
    return this.production.outpostPiTestHarness.meshPeers();
  }

  /** Return broker-issued mesh identity and peers without composing addresses. */
  async meshStatus(): Promise<{ address: string | null; bridgeActive: boolean; peers: readonly string[] }> {
    return {
      address: this.production.outpostPiTestHarness.meshAddress(),
      bridgeActive: this.production.outpostPiTestHarness.meshBridgeActive(),
      peers: await this.production.outpostPiTestHarness.meshPeers(),
    };
  }

  /** Resolve a test route from signed membership and a broker-issued address. */
  meshTarget(pcPubkey: string, remoteAddress: string): string | null {
    return this.production.outpostPiTestHarness.meshTarget(pcPubkey, remoteAddress);
  }

  /** Send below the linked roster cache while retaining relay and ingress behavior. */
  sendDirectMeshMessage(input: {
    toPc: string;
    toRoom: string;
    toAddress: string;
    message: string;
  }): boolean {
    return this.production.outpostPiTestHarness.sendDirectMeshMessage({
      toPc: input.toPc,
      toRoom: input.toRoom,
      toAddress: input.toAddress,
      body: { type: "e2e_mesh", message: input.message },
    });
  }

  /** Emit one allowlisted background-subagent lifecycle edge on the SDK bus. */
  emitBackgroundLifecycle(event: BackgroundLifecycleEvent, id: string): void {
    this.eventBus.emit(`subagents:${event}`, { id });
  }

  /** Arm the next SDK user-message action to settle only on explicit release. */
  deferNextTurn(reply?: string): PiHostTurnControlStatus {
    if (this.turnControlPhase === "armed" || this.turnControlPhase === "pending") {
      throw new Error("a deferred turn is already active");
    }
    this.stagedReply = reply ?? null;
    this.turnControlPhase = "armed";
    return this.turnControlStatus();
  }

  /** Release the currently deferred SDK user-message action. */
  resolveDeferredTurn(): PiHostTurnControlStatus {
    if (this.turnControlPhase !== "pending" || !this.deferredTurnResolve) {
      throw new Error("no deferred turn is pending");
    }
    const resolve = this.deferredTurnResolve;
    this.deferredTurnResolve = null;
    resolve();
    return this.turnControlStatus();
  }

  turnControlStatus(): PiHostTurnControlStatus {
    return { phase: this.turnControlPhase };
  }

  /** Fence production owner ingress without fabricating an app response. */
  async beginDeliveryQuiesce(): Promise<PiHostDeliveryControlStatus> {
    this.production._setHotReloadingForTest(true);
    return this.deliveryControlStatus();
  }

  /** Report production-fence state and actual SDK adapter delivery count. */
  async deliveryControlStatus(): Promise<PiHostDeliveryControlStatus> {
    await this.production._drainOwnerChannelsForTest();
    return {
      fenced: this.production._getOwnerDeliveryFenceReasonForTest() !== null,
      sdkDeliveryCount: this.sdkDeliveryCount,
    };
  }

  /** List session identities retained by this process-local live test host. */
  sessionIds(): readonly string[] {
    return [...this.sessions.keys()];
  }

  /** Model an external Pi `/resume` switch to a retained SDK session. */
  async switchSession(sessionId: string): Promise<void> {
    if (this.disposed) throw new Error("Pi host runtime is disposed");
    const next = this.sessions.get(sessionId);
    if (!next) throw new Error("unknown retained session");
    if (next === this.sessionManager) return;

    const before = await this.runner.emit({ type: "session_before_switch", reason: "resume" });
    if (before?.cancel) throw new Error("session switch cancelled");
    this.sessionManager = next;
    (this.runner as unknown as { sessionManager: SessionManager }).sessionManager = next;
    this.runner.bindCore(actions(
      next,
      this.record.bind(this),
      (content) => this.handleSendUserMessage(content),
    ), contextActions(this.cwd));
    await this.runner.emit({ type: "session_start", reason: "resume" });
  }

  /** Gracefully leave the mesh and return the assigned name for respawn. */
  async preparePreservingRestart(): Promise<string> {
    const assignedName = this.production.outpostPiTestHarness.name()
      ?? this.production._getLockedNameForTest()
      ?? defaultAgentName(this.cwd);
    await this.invokeOutpostPi("stop");
    this.production._resetCwdLockForTest();
    return assignedName;
  }

  async dispose(): Promise<void> {
    if (this.disposed) return;
    this.disposed = true;
    await this.runner.emit({ type: "session_shutdown", reason: "quit" });
    this.runner.invalidate("e2e host disposed");
  }

  private record(kind: PiHostTuiEvent["kind"], payload: unknown): void {
    this.events.push({ seq: ++this.seq, kind, payload });
    if (this.events.length > 200) this.events.splice(0, this.events.length - 200);
  }

  private async replaceSession(
    options?: Parameters<ExtensionCommandContextActions["newSession"]>[0],
  ): Promise<{ cancelled: boolean }> {
    const before = await this.runner.emit({ type: "session_before_switch", reason: "new" });
    if (before?.cancel) return { cancelled: true };

    const previousSessionFile = this.sessionManager.getSessionFile();
    const sessionDir = this.sessionManager.getSessionDir();
    this.sessionManager = SessionManager.create(this.cwd, sessionDir, {
      parentSession: options?.parentSession,
    });
    this.sessions.set(this.sessionManager.getSessionId(), this.sessionManager);
    // The narrow host keeps one SDK runner but rotates the actual
    // SessionManager. ExtensionRunner's runtime getter then exposes the fresh
    // session identity to session_start and the replacement context.
    (this.runner as unknown as { sessionManager: SessionManager }).sessionManager = this.sessionManager;
    this.runner.bindCore(actions(
      this.sessionManager,
      this.record.bind(this),
      (content) => this.handleSendUserMessage(content),
    ), contextActions(this.cwd));
    await this.runner.emit({ type: "session_start", reason: "new", previousSessionFile });
    await options?.setup?.(this.sessionManager);

    if (options?.withSession) {
      const context = Object.defineProperties(
        {},
        Object.getOwnPropertyDescriptors(this.runner.createCommandContext()),
      ) as ReturnType<ExtensionRunner["createCommandContext"]> & {
        sendMessage: (...args: Parameters<ExtensionActions["sendMessage"]>) => Promise<void>;
        sendUserMessage: (...args: Parameters<ExtensionActions["sendUserMessage"]>) => Promise<void>;
      };
      context.sendMessage = async (message) => {
        actionsSendMessage(this.sessionManager, this.record.bind(this), message);
      };
      context.sendUserMessage = async (content) => this.handleSendUserMessage(content);
      await options.withSession(context);
    }
    return { cancelled: false };
  }

  private async handleSendUserMessage(
    content: Parameters<ExtensionActions["sendUserMessage"]>[0],
  ): Promise<void> {
    this.sdkDeliveryCount += 1;
    const message = { role: "user" as const, content, timestamp: Date.now() };
    this.sessionManager.appendMessage(message as never);
    await this.runner.emitMessageEnd({ type: "message_end", message: message as never });

    if (this.turnControlPhase !== "armed") return;
    await this.runner.emit({ type: "agent_start" });
    this.turnControlPhase = "pending";
    await new Promise<void>((resolve) => { this.deferredTurnResolve = resolve; });
    const stagedReply = this.stagedReply;
    this.stagedReply = null;
    if (stagedReply !== null) {
      const assistant = {
        role: "assistant" as const,
        content: [{ type: "text" as const, text: stagedReply }],
        timestamp: Date.now(),
      };
      this.sessionManager.appendMessage(assistant as never);
      await this.runner.emitMessageEnd({ type: "message_end", message: assistant as never });
    }
    await this.runner.emit({ type: "agent_end", messages: [] });
    await this.runner.emit({ type: "agent_settled" });
    this.turnControlPhase = "settled";
  }
}

async function realSdkFactoryLoader(): Promise<LoadExtensionFromFactory> {
  const packageEntry = fileURLToPath(import.meta.resolve("@earendil-works/pi-coding-agent"));
  const loaderUrl = pathToFileURL(join(dirname(packageEntry), "core/extensions/loader.js")).href;
  const module = await import(loaderUrl) as { loadExtensionFromFactory?: LoadExtensionFromFactory };
  if (typeof module.loadExtensionFromFactory !== "function") {
    throw new Error("installed Pi SDK does not expose its factory loader implementation");
  }
  return module.loadExtensionFromFactory;
}

function actions(
  sessionManager: SessionManager,
  record: (kind: PiHostTuiEvent["kind"], payload: unknown) => void,
  sendUserMessage: ExtensionActions["sendUserMessage"],
): ExtensionActions {
  return {
    sendMessage: (message) => actionsSendMessage(sessionManager, record, message),
    sendUserMessage,
    appendEntry: (customType, data) => { sessionManager.appendCustomEntry(customType, data); },
    setSessionName: (name) => { sessionManager.appendSessionInfo(name); },
    getSessionName: () => sessionManager.getSessionName(),
    setLabel: (entryId, label) => { sessionManager.appendLabelChange(entryId, label); },
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

function actionsSendMessage(
  sessionManager: SessionManager,
  record: (kind: PiHostTuiEvent["kind"], payload: unknown) => void,
  message: Parameters<ExtensionActions["sendMessage"]>[0],
): void {
  sessionManager.appendCustomMessageEntry(
    message.customType,
    message.content,
    message.display,
    message.details,
  );
  record("tui_message", message);
}

function contextActions(cwd: string): ExtensionContextActions {
  return {
    getModel: () => undefined,
    getScopedModels: () => [],
    isIdle: () => true,
    isProjectTrusted: () => true,
    getSignal: () => undefined,
    abort: () => undefined,
    hasPendingMessages: () => false,
    shutdown: () => undefined,
    getContextUsage: () => undefined,
    compact: () => undefined,
    getSystemPrompt: () => "",
    getSystemPromptOptions: () => ({ cwd }),
  };
}

function ui(record: (kind: PiHostTuiEvent["kind"], payload: unknown) => void) {
  return {
    notify: (message: string, type = "info") => record("notification", { message, type }),
    setStatus: () => undefined,
    setTitle: () => undefined,
    select: async () => undefined,
    confirm: async () => false,
    input: async () => undefined,
  };
}

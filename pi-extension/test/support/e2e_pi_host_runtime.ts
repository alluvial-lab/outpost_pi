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

export interface PiHostStatus {
  readonly generation: string;
  readonly state: "idle" | "started" | "paired";
  readonly sessionId: string;
  readonly roomId: string;
  readonly relayConnected: boolean;
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

type ProductionModule = {
  default: ExtensionFactory;
  outpostPiTestHarness: {
    state(): "idle" | "started" | "paired";
    /** The room this Pi actually registered with the relay; null while idle. */
    roomId(): string | null;
  };
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
  private deferredTurnResolve: (() => void) | null = null;

  private constructor(
    private readonly cwd: string,
    private sessionManager: SessionManager,
    private readonly runner: ExtensionRunner,
    private readonly production: ProductionModule,
    private readonly sessionContextHasMessageActions: boolean,
  ) {}

  static async start(options: {
    relayUrl: string;
    cwd: string;
    seededTranscriptText: string;
  }): Promise<E2ePiHostRuntime> {
    process.env.OUTPOST_PI_RELAY = options.relayUrl;
    process.env.OUTPOST_PI_DIRECT_CONFIG = JSON.stringify({
      agent_name: "e2e-agent",
      auto_start_relay: true,
    });
    process.env.OUTPOST_PI_ALLOW_FILE_IDENTITY = "1";

    // HOME is fixed by Compose before Node starts, so modules that resolve
    // homedir() at import time see this isolated path. Clear all prior state on
    // every process generation rather than inventing in-process reset hooks.
    rmSync(homedir(), { recursive: true, force: true });
    rmSync(options.cwd, { recursive: true, force: true });
    // The headless pair-code seam lives outside HOME and the extension refuses
    // to overwrite a pre-existing target (symlink-attack hardening), so a stale
    // file from an earlier generation would 500 every later `pair` command.
    const pairCodeFile = process.env.OUTPOST_PI_PAIR_CODE_FILE;
    if (pairCodeFile) rmSync(pairCodeFile, { force: true });
    mkdirSync(homedir(), { recursive: true, mode: 0o700 });
    mkdirSync(options.cwd, { recursive: true });

    const sessionDir = join(homedir(), ".pi", "e2e-sessions");
    const sessionManager = SessionManager.create(options.cwd, sessionDir);
    sessionManager.appendMessage({
      role: "user",
      content: options.seededTranscriptText,
    } as never);

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
      production,
      typeof sessionContext.sendMessage === "function"
        || typeof sessionContext.sendUserMessage === "function",
    );
    await runner.emit({ type: "session_start", reason: "startup" });
    await instance.invokeOutpostPi("");
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
      roomId: this.production.outpostPiTestHarness.roomId() ?? roomIdFor(this.cwd, "e2e-agent"),
      relayConnected: state !== "idle",
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

  /** Arm the next SDK user-message action to settle only on explicit release. */
  deferNextTurn(): PiHostTurnControlStatus {
    if (this.turnControlPhase === "armed" || this.turnControlPhase === "pending") {
      throw new Error("a deferred turn is already active");
    }
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
    const message = { role: "user" as const, content, timestamp: Date.now() };
    this.sessionManager.appendMessage(message as never);
    await this.runner.emitMessageEnd({ type: "message_end", message: message as never });

    if (this.turnControlPhase !== "armed") return;
    this.turnControlPhase = "pending";
    await new Promise<void>((resolve) => { this.deferredTurnResolve = resolve; });
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

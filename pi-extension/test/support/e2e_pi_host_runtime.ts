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

type ProductionModule = {
  default: ExtensionFactory;
  outpostPiTestHarness: { state(): "idle" | "started" | "paired" };
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

  private constructor(
    private readonly cwd: string,
    private readonly sessionManager: SessionManager,
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
    ), contextActions(options.cwd));
    runner.bindCommandContext({
      waitForIdle: async () => undefined,
      newSession: async () => ({ cancelled: false }),
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
      roomId: roomIdFor(this.cwd, "e2e-agent"),
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
): ExtensionActions {
  return {
    sendMessage: (message) => {
      sessionManager.appendCustomMessageEntry(
        message.customType,
        message.content,
        message.display,
        message.details,
      );
      record("tui_message", message);
    },
    sendUserMessage: () => undefined,
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

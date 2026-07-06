/**
 * SPIKE ONLY — Unit 7 / feature-cross-side-observability.
 *
 * This file probes whether the installed Pi SDK's ExtensionRunner can be driven
 * headlessly from Vitest for session-replacement coverage. It intentionally
 * distinguishes direct ExtensionRunner support from a higher-level
 * AgentSessionRuntime seam; do not treat the simulated seam below as proof that
 * ExtensionRunner alone performs real /new, /reload, or /resume replacement.
 */
import {
  AgentSessionRuntime,
  createExtensionRuntime,
  ExtensionRunner,
  SessionManager,
  type Extension,
  type ExtensionActions,
  type ExtensionCommandContextActions,
  type ReplacedSessionContext,
  type SessionStartEvent,
  type SessionShutdownEvent,
} from "@earendil-works/pi-coding-agent";
import { describe, expect, test, vi } from "vitest";

type Delivery = { sessionLabel: string; content: unknown };
type LifecycleEvent =
  | { type: "session_start"; reason: SessionStartEvent["reason"]; sessionId: string }
  | { type: "session_shutdown"; reason: SessionShutdownEvent["reason"]; sessionId: string };

type RunnerBundle = {
  runner: ExtensionRunner;
  sessionManager: SessionManager;
};

function makeExtension(events: LifecycleEvent[]): Extension {
  const handlers = new Map<string, Array<(...args: unknown[]) => Promise<unknown>>>([
    [
      "session_start",
      [async (event: unknown, ctx: unknown) => {
        const typedEvent = event as SessionStartEvent;
        const typedCtx = ctx as { sessionManager: { getSessionId(): string } };
        events.push({
          type: "session_start",
          reason: typedEvent.reason,
          sessionId: typedCtx.sessionManager.getSessionId(),
        });
      }],
    ],
    [
      "session_shutdown",
      [async (event: unknown, ctx: unknown) => {
        const typedEvent = event as SessionShutdownEvent;
        const typedCtx = ctx as { sessionManager: { getSessionId(): string } };
        events.push({
          type: "session_shutdown",
          reason: typedEvent.reason,
          sessionId: typedCtx.sessionManager.getSessionId(),
        });
      }],
    ],
  ]);

  return {
    path: "<spike-inline-extension>",
    resolvedPath: "<spike-inline-extension>",
    sourceInfo: { path: "<spike-inline-extension>" },
    handlers,
    tools: new Map(),
    messageRenderers: new Map(),
    commands: new Map(),
    flags: new Map(),
    shortcuts: new Map(),
  } as unknown as Extension;
}

function makeActions(deliveries: Delivery[], sessionLabel: string): ExtensionActions {
  return {
    sendMessage: vi.fn(),
    sendUserMessage: vi.fn((content: unknown) => {
      deliveries.push({ sessionLabel, content });
    }),
    appendEntry: vi.fn(),
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

function makeContextActions() {
  return {
    getModel: () => undefined,
    isIdle: () => true,
    isProjectTrusted: () => true,
    getSignal: () => undefined,
    abort: vi.fn(),
    hasPendingMessages: () => false,
    shutdown: vi.fn(),
    getContextUsage: () => undefined,
    compact: vi.fn(),
    getSystemPrompt: () => "",
    getSystemPromptOptions: () => ({ cwd: "/tmp/remote-pi-extension-runner-spike" }),
  };
}

function makeRunnerBundle(
  label: string,
  events: LifecycleEvent[],
  deliveries: Delivery[],
  cwd = "/tmp/remote-pi-extension-runner-spike",
  sessionManager = SessionManager.inMemory(cwd),
): RunnerBundle {
  const runtime = createExtensionRuntime();
  const runner = new ExtensionRunner(
    [makeExtension(events)],
    runtime,
    cwd,
    sessionManager,
    {} as never,
  );
  runner.bindCore(makeActions(deliveries, label), makeContextActions());
  return { runner, sessionManager };
}

function bindCommandActions(
  runner: ExtensionRunner,
  actions: Partial<ExtensionCommandContextActions>,
): void {
  const notUsed = async () => ({ cancelled: false });
  runner.bindCommandContext({
    waitForIdle: async () => undefined,
    newSession: actions.newSession ?? notUsed,
    fork: actions.fork ?? (async () => ({ cancelled: false })),
    navigateTree: actions.navigateTree ?? (async () => ({ cancelled: false })),
    switchSession: actions.switchSession ?? notUsed,
    reload: actions.reload ?? (async () => undefined),
  });
}

function makeFakeSession(
  label: string,
  runner: ExtensionRunner,
  sessionManager: SessionManager,
  deliveries: Delivery[],
) {
  return {
    extensionRunner: runner,
    sessionManager,
    sessionFile: sessionManager.getSessionFile(),
    agent: { state: { messages: [] as unknown[] } },
    dispose: () => {
      runner.invalidate();
    },
    createReplacedSessionContext: () => {
      const context = Object.defineProperties(
        {},
        Object.getOwnPropertyDescriptors(runner.createCommandContext()),
      ) as ReplacedSessionContext;
      context.sendUserMessage = async (content: unknown) => {
        deliveries.push({ sessionLabel: label, content });
      };
      context.sendMessage = async (message: unknown) => {
        deliveries.push({ sessionLabel: label, content: message });
      };
      return context;
    },
  };
}

describe("SPIKE: ExtensionRunner headless feasibility", () => {
  test("ExtensionRunner can be instantiated headlessly and create a real ExtensionContext", () => {
    const events: LifecycleEvent[] = [];
    const deliveries: Delivery[] = [];
    const { runner, sessionManager } = makeRunnerBundle("initial", events, deliveries);

    const ctx = runner.createContext();

    expect(ctx.cwd).toBe("/tmp/remote-pi-extension-runner-spike");
    expect(ctx.sessionManager.getSessionId()).toBe(sessionManager.getSessionId());
    expect(ctx.isIdle()).toBe(true);
    expect("newSession" in ctx).toBe(false);
    expect("sendUserMessage" in ctx).toBe(false);
  });

  test("createCommandContext exposes newSession, but ExtensionRunner's default handler does not replace the session", async () => {
    const events: LifecycleEvent[] = [];
    const deliveries: Delivery[] = [];
    const { runner, sessionManager } = makeRunnerBundle("initial", events, deliveries);
    const commandCtx = runner.createCommandContext();
    const beforeSessionId = commandCtx.sessionManager.getSessionId();
    const withSession = vi.fn();

    const result = await commandCtx.newSession({ withSession });

    expect(result).toEqual({ cancelled: false });
    expect(withSession).not.toHaveBeenCalled();
    expect(commandCtx.sessionManager.getSessionId()).toBe(beforeSessionId);
    expect(sessionManager.getSessionId()).toBe(beforeSessionId);
  });

  test("a bound command newSession is only host delegation, not replacement performed by ExtensionRunner itself", async () => {
    const events: LifecycleEvent[] = [];
    const deliveries: Delivery[] = [];
    const { runner } = makeRunnerBundle("initial", events, deliveries);
    const freshSendUserMessage = vi.fn(async (_content: unknown) => undefined);
    bindCommandActions(runner, {
      newSession: async (options) => {
        const fresh = {
          ...runner.createCommandContext(),
          sendMessage: vi.fn(async () => undefined),
          sendUserMessage: freshSendUserMessage,
        } as unknown as ReplacedSessionContext;
        await options?.withSession?.(fresh);
        return { cancelled: false };
      },
    });

    const commandCtx = runner.createCommandContext();
    await commandCtx.newSession({
      withSession: async (freshCtx) => {
        await freshCtx.sendUserMessage("post-replacement");
      },
    });

    expect(freshSendUserMessage).toHaveBeenCalledWith("post-replacement");
    // No lifecycle events fired: the test supplied a fake host handler. This is
    // why this path is not evidence that ExtensionRunner itself can drive /new.
    expect(events).toEqual([]);
  });
});

describe("SPIKE: higher-level SDK seam around AgentSessionRuntime", () => {
  test("AgentSessionRuntime can exercise stale old ctx + withSession delivery with a fake AgentSession shell", async () => {
    const events: LifecycleEvent[] = [];
    const deliveries: Delivery[] = [];
    let sequence = 0;
    let host: AgentSessionRuntime | null = null;

    async function createFakeRuntime(options: {
      cwd: string;
      agentDir: string;
      sessionManager: SessionManager;
      sessionStartEvent?: SessionStartEvent;
    }) {
      sequence += 1;
      const label = sequence === 1 ? "initial" : `replacement-${sequence}`;
      const { runner, sessionManager } = makeRunnerBundle(
        label,
        events,
        deliveries,
        options.cwd,
        options.sessionManager,
      );
      const session = makeFakeSession(label, runner, sessionManager, deliveries);
      if (options.sessionStartEvent) {
        await runner.emit(options.sessionStartEvent);
      }
      return {
        session,
        services: { cwd: options.cwd, agentDir: options.agentDir },
        diagnostics: [],
      };
    }

    const initial = await createFakeRuntime({
      cwd: "/tmp/remote-pi-extension-runner-spike",
      agentDir: "/tmp/remote-pi-extension-runner-spike/.pi",
      sessionManager: SessionManager.inMemory("/tmp/remote-pi-extension-runner-spike"),
      sessionStartEvent: { type: "session_start", reason: "startup" },
    });

    host = new AgentSessionRuntime(
      initial.session as never,
      initial.services as never,
      createFakeRuntime,
    );

    function rebind(session: { extensionRunner: ExtensionRunner }): void {
      bindCommandActions(session.extensionRunner, {
        newSession: (options) => host!.newSession(options),
        reload: async () => session.extensionRunner.invalidate(),
      });
    }

    rebind(initial.session);
    host.setRebindSession(async (session) => rebind(session as { extensionRunner: ExtensionRunner }));

    const oldCommandCtx = initial.session.extensionRunner.createCommandContext();
    const oldSessionId = oldCommandCtx.sessionManager.getSessionId();
    let freshSessionId: string | undefined;

    const result = await oldCommandCtx.newSession({
      withSession: async (freshCtx) => {
        freshSessionId = freshCtx.sessionManager.getSessionId();
        await freshCtx.sendUserMessage("message after replacement");
      },
    });

    expect(result).toEqual({ cancelled: false });
    expect(freshSessionId).toBeDefined();
    expect(freshSessionId).not.toBe(oldSessionId);
    expect(() => oldCommandCtx.cwd).toThrow(/stale after session replacement or reload/);
    expect(events.map((event) => `${event.type}:${event.reason}`)).toEqual([
      "session_start:startup",
      "session_shutdown:new",
      "session_start:new",
    ]);
    expect(deliveries).toEqual([
      { sessionLabel: "replacement-2", content: "message after replacement" },
    ]);
  });
});

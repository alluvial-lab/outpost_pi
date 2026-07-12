import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SessionManager, type ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { afterEach, describe, expect, test } from "vitest";
import {
  SdkSessionReplacementHarness,
  TestPeerChannel,
  type Delivery,
} from "./support/sdk_session_replacement_harness.js";
import type { ClientMessage, ServerMessage } from "../src/protocol/types.js";

const STALE_CTX = /stale after session replacement or reload/;

let cleanupPaths: string[] = [];
let harnesses: SdkSessionReplacementHarness[] = [];

afterEach(async () => {
  for (const harness of harnesses.splice(0).reverse()) {
    await harness.dispose().catch(() => undefined);
  }
  for (const path of cleanupPaths.splice(0).reverse()) {
    rmSync(path, { recursive: true, force: true });
  }
});

function makeTempCwd(): string {
  const cwd = mkdtempSync(join(tmpdir(), "outpost-pi-session-harness-"));
  cleanupPaths.push(cwd);
  return cwd;
}

async function makeHarness(cwd = makeTempCwd()): Promise<SdkSessionReplacementHarness> {
  const harness = await SdkSessionReplacementHarness.create({ cwd });
  harnesses.push(harness);
  return harness;
}

function withCurrentSession(harness: SdkSessionReplacementHarness, msg: Omit<ClientMessage, "session_id">): ClientMessage {
  return { ...msg, session_id: harness.currentRemoteSessionId() } as ClientMessage;
}

async function routeAndWaitForActionOk(
  harness: SdkSessionReplacementHarness,
  msg: Omit<ClientMessage, "session_id">,
): Promise<{ channel: TestPeerChannel; ack: ServerMessage }> {
  const channel = new TestPeerChannel();
  harness.routeCurrent(withCurrentSession(harness, msg), channel);
  const ack = await channel.waitForMessage((m) =>
    m.type === "action_ok" && "in_reply_to" in m && m.in_reply_to === (msg as { id: string }).id,
  );
  return { channel, ack };
}

describe("SDK session replacement harness", () => {
  test("direct SDK newSession emits session_start:new on the actual extension and makes the old ctx stale", async () => {
    const harness = await makeHarness();
    const oldCommandCtx = await harness.primeCommandContext();
    const oldSessionId = oldCommandCtx.sessionManager.getSessionId();
    let freshSessionId: string | undefined;

    const result = await oldCommandCtx.newSession({
      withSession: async (freshCtx) => {
        freshSessionId = freshCtx.sessionManager.getSessionId();
      },
    });

    expect(result).toEqual({ cancelled: false });
    expect(freshSessionId).toBeDefined();
    expect(freshSessionId).not.toBe(oldSessionId);
    // The actual Outpost-Pi session_start hook captured the fresh ExtensionContext.
    expect(harness.currentModule._getRemoteSessionIdForTest()).toBe(freshSessionId);
    expect(harness.lifecycleEvents.map((event) => `${event.type}:${event.reason}`)).toEqual([
      "session_start:startup",
      "session_shutdown:new",
      "session_start:new",
    ]);
    // Real teeth: this is the SDK's guarded getter, backed by ExtensionRunner.assertActive().
    expect(() => oldCommandCtx.cwd).toThrow(STALE_CTX);
  });

  test("app session_new delegates to runtime newSession({ withSession }) and the replacement callback delivers on the fresh ctx", async () => {
    const harness = await makeHarness();
    await harness.primeCommandContext();
    const oldModule = harness.currentModule;
    const oldCommandCtx = harness.createCommandContext();
    const oldSessionId = harness.currentRemoteSessionId();

    const { ack } = await routeAndWaitForActionOk(harness, {
      type: "session_new",
      id: "new-from-app",
    } as Omit<ClientMessage, "session_id">);

    expect(ack).toMatchObject({ type: "action_ok", in_reply_to: "new-from-app", action: "session_new" });
    expect(harness.newSessionCalls).toEqual([{ sessionLabel: "initial", hasWithSession: true }]);
    expect(harness.currentRemoteSessionId()).not.toBe(oldSessionId);
    expect(() => oldCommandCtx.cwd).toThrow(STALE_CTX);

    const reboundSessionId = oldModule._getRemoteSessionIdForTest();
    expect(reboundSessionId).toBe(harness.currentRemoteSessionId());

    const oldModuleChannel = new TestPeerChannel();
    oldModule._routeClientMessageFrom(
      oldModuleChannel,
      {
        type: "user_message",
        id: "post-new-user-message",
        session_id: reboundSessionId!,
        text: "message after app-triggered replacement",
      },
      harness.currentRunner.createCommandContext(),
    );

    const delivery = await harness.waitForDelivery((candidate: Delivery) =>
      candidate.sessionLabel === "replacement-2" &&
      candidate.method === "sendUserMessage" &&
      JSON.stringify(candidate.content).includes("message after app-triggered replacement"),
    );
    expect(delivery.sessionLabel).toBe("replacement-2");
  });

  test("subsequent app actions route through the fresh session ctx after app-triggered replacement", async () => {
    const harness = await makeHarness();
    await harness.primeCommandContext();

    await routeAndWaitForActionOk(harness, {
      type: "session_new",
      id: "new-before-compact",
    } as Omit<ClientMessage, "session_id">);

    const { ack } = await routeAndWaitForActionOk(harness, {
      type: "session_compact",
      id: "compact-after-new",
    } as Omit<ClientMessage, "session_id">);

    expect(ack).toMatchObject({ type: "action_ok", in_reply_to: "compact-after-new", action: "session_compact" });
    expect(harness.compactCalls).toHaveLength(1);
    expect(harness.compactCalls[0]).toMatchObject({ sessionLabel: "replacement-2" });
  });

  test("a second app session_new after replacement proves the fresh ctx is command-capable (onReplaced rebind teeth)", async () => {
    // [I1] teeth: the first session_new proves the SDK invalidates the old
    // ctx and the extension captures the fresh session id via session_start.
    // But fresh delivery can pass through the factory-bound message API even
    // if the extension's onReplaced/_bindReplacementSessionContext() rebind
    // is broken. A SECOND session_new requires the fresh ctx to be
    // command-capable (it must route the action → runtime.newSession again,
    // rotating the session id a second time). If the extension held a stale
    // command ctx after the first replacement, this second session_new would
    // either throw stale or fail to rotate the id — so this test has teeth
    // for the onReplaced rebind that the prior tests lack.
    const harness = await makeHarness();
    await harness.primeCommandContext();

    const firstSessionId = harness.currentRemoteSessionId();

    await routeAndWaitForActionOk(harness, {
      type: "session_new",
      id: "first-new",
    } as Omit<ClientMessage, "session_id">);

    const secondSessionId = harness.currentRemoteSessionId();
    expect(secondSessionId).not.toBe(firstSessionId);

    const { ack } = await routeAndWaitForActionOk(harness, {
      type: "session_new",
      id: "second-new",
    } as Omit<ClientMessage, "session_id">);

    expect(ack).toMatchObject({ type: "action_ok", in_reply_to: "second-new", action: "session_new" });
    // The second newSession call must come from the FRESH (replacement-2)
    // session, proving the post-replacement ctx is command-capable — not
    // the initial session.
    expect(harness.newSessionCalls).toContainEqual({
      sessionLabel: "replacement-2",
      hasWithSession: true,
    });
    // And the session id rotated a second time.
    const thirdSessionId = harness.currentRemoteSessionId();
    expect(thirdSessionId).not.toBe(secondSessionId);
  });

  test("resume-style session_start backfills history from SessionManager.buildSessionContext", async () => {
    const cwd = makeTempCwd();
    const harness = await makeHarness(cwd);
    const sessionDir = mkdtempSync(join(tmpdir(), "outpost-pi-session-harness-sessions-"));
    cleanupPaths.push(sessionDir);
    const persisted = SessionManager.create(cwd, sessionDir);
    persisted.appendMessage({ role: "user", content: "hello before pairing" } as never);
    persisted.appendMessage({
      role: "assistant",
      content: [{ type: "text", text: "hello from persisted history" }],
    } as never);
    const sessionFile = persisted.getSessionFile();
    if (!sessionFile) throw new Error("Expected persisted session file");

    await harness.resumeSession(sessionFile);

    expect(harness.lifecycleEvents.map((event) => `${event.type}:${event.reason}`)).toEqual([
      "session_start:startup",
      "session_shutdown:resume",
      "session_start:resume",
    ]);
    expect(harness.currentModule._getRemoteSessionIdForTest()).toBe(harness.currentRunner.createContext().sessionManager.getSessionId());

    const channel = new TestPeerChannel();
    harness.routeCurrent(withCurrentSession(harness, {
      type: "session_sync",
      id: "sync-after-resume",
    } as Omit<ClientMessage, "session_id">), channel);

    const history = await channel.waitForMessage((msg) =>
      msg.type === "session_history" && msg.in_reply_to === "sync-after-resume",
    ) as Extract<ServerMessage, { type: "session_history" }>;

    expect(history.events.map((event) => event.type)).toEqual(["user_input", "agent_message"]);
    expect(history.events[0]).toMatchObject({ text: "hello before pairing" });
    expect(history.events[1]).toMatchObject({ text: "hello from persisted history" });
  });
});

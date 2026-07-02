import { describe, expect, test, vi } from "vitest";
import { SdkSessionProjection, isAgentMessageApi } from "./sdk_session_projection.js";

/**
 * Regression coverage for the pair-code QR-not-rendering bug.
 *
 * Root cause: `bindSessionContext(ctx)` called `replaceSessionCapabilities(ctx)`,
 * which UNCONDITIONALLY sets `messageApi = isAgentMessageApi(ctx) ? ctx : null`.
 * The `ExtensionContext` Pi emits with `session_start` (built by
 * `ExtensionRunner.createContext()` in the SDK) does NOT carry
 * `sendMessage`/`sendUserMessage` — only `ExtensionAPI` (the factory `pi`) and
 * `ReplacedSessionContext` do. So every `session_start` (including startup)
 * nulled the valid `messageApi` armed at factory init by `bindApi(pi)`, making
 * `sendPiMessage` return false and silently dropping the pair-code QR.
 *
 * The pre-split code used `bindCapabilities` (additive: only sets when the
 * value is an AgentMessageApi), so a ctx lacking those methods was a no-op.
 * These tests pin that contract against a REALISTIC session_start ctx.
 */
function makeOutputs() {
  return {
    broadcast: vi.fn(),
    sendTo: vi.fn(),
    publishRoomMeta: vi.fn(),
    activeOwnerIds: () => [] as readonly string[],
    lateAttachTargets: () => [] as readonly { peerId: string; channel: never }[],
    handleClientMessage: vi.fn(),
  };
}

/** A realistic `ExtensionAPI`-shaped object carrying the message methods. */
function makePi() {
  return {
    sendMessage: vi.fn(),
    sendUserMessage: vi.fn(),
  };
}

/** A realistic `ExtensionContext` from `ExtensionRunner.createContext()` —
 *  carries ui/cwd/abort/compact/sessionManager but NO sendMessage/sendUserMessage. */
function makeSessionStartCtx() {
  return {
    ui: { notify: vi.fn() },
    cwd: "/home/user/proj",
    abort: vi.fn(),
    compact: vi.fn(),
    sessionManager: { getSessionId: () => "session-1" },
    isIdle: () => true,
  };
}

describe("SdkSessionProjection messageApi binding across session_start", () => {
  test("isAgentMessageApi is false for a realistic session_start ctx (no sendMessage)", () => {
    expect(isAgentMessageApi(makeSessionStartCtx())).toBe(false);
  });

  test("bindApi(pi) arms messageApi; a realistic session_start must NOT null it", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    const pi = makePi();
    projection.bindApi(pi);

    // Armed at factory init.
    expect(projection.messageApiBinding()).toBe(pi);

    // session_start fires with a ctx that lacks sendMessage/sendUserMessage.
    projection.bindSessionContext(makeSessionStartCtx());

    // The pi-armed binding must survive (this is what pair-code relies on).
    expect(projection.messageApiBinding()).toBe(pi);
    expect(projection.sendPiMessage({ customType: "remote-pi:pair-code", content: "qr", display: true }))
      .toBe(true);
    expect(pi.sendMessage).toHaveBeenCalledTimes(1);
  });

  test("bindSessionContext with an AgentMessageApi-shaped ctx still rebinds to it", () => {
    // A ReplacedSessionContext (newSession/fork/switch withSession) DOES carry
    // sendMessage/sendUserMessage and must take over the binding. This is the
    // path the regression's overly-broad replacement was trying to serve.
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());
    const fresh = makePi();
    projection.bindSessionContext(fresh as never);
    expect(projection.messageApiBinding()).toBe(fresh);
  });
});

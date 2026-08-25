import { describe, expect, test, vi } from "vitest";
import {
  SdkSessionProjection,
  isAgentMessageApi,
  isTranscriptEntryApi,
} from "./sdk_session_projection.js";
import { TRANSCRIPT_EVENT_CUSTOM_TYPE } from "./durable_transcript_event.js";
import type { TranscriptEvent } from "./transcript_event.js";
import type { LegacyAgentMessage, SdkTranscriptContextEntry } from "./transcript_projection.js";
import { FakeDeliveryDebugLog } from "./delivery_debug_log.test.js";

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
    appendEntry: vi.fn(),
  };
}

function durableUser(eventId = "durable-user-1"): TranscriptEvent {
  return {
    kind: "user_confirmed",
    eventId,
    sessionId: "session-1",
    ts: 1_234,
    clientMessageId: "client-1",
    text: "persist me",
  };
}

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
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
    expect(projection.sendPiMessage({ customType: "outpost-pi:pair-code", content: "qr", display: true }))
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

describe("SdkSessionProjection durable transcript binding", () => {
  test("narrows appendEntry separately from message delivery capabilities", () => {
    expect(isTranscriptEntryApi({ appendEntry: vi.fn() })).toBe(true);
    expect(isTranscriptEntryApi({ sendMessage: vi.fn(), sendUserMessage: vi.fn() })).toBe(false);
    expect(isAgentMessageApi({ appendEntry: vi.fn() })).toBe(false);
  });

  test("writes one exact v1 entry before exposing the event in memory", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    const pi = makePi();
    const event = durableUser();
    pi.appendEntry.mockImplementation(() => {
      expect(projection.getTranscriptEventsForTest()).toEqual([]);
    });
    projection.bindApi(pi);

    expect(projection.recordDurableTranscriptEvent(event)).toEqual({ status: "recorded" });
    expect(pi.appendEntry).toHaveBeenCalledOnce();
    expect(pi.appendEntry).toHaveBeenCalledWith(TRANSCRIPT_EVENT_CUSTOM_TYPE, event);
    expect(projection.getTranscriptEventsForTest()).toEqual([event]);
    expect(projection.recordedTranscriptTs(event.eventId)).toBe(event.ts);
    expect(projection.recordDurableTranscriptEvent({ ...event, ts: 9_999 })).toEqual({ status: "duplicate" });
    expect(pi.appendEntry).toHaveBeenCalledOnce();
  });

  test("missing and throwing append capabilities do not create in-memory authority", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    const event = durableUser();
    projection.bindApi({ sendMessage: vi.fn(), sendUserMessage: vi.fn() } as never);
    expect(projection.recordDurableTranscriptEvent(event)).toEqual({ status: "unavailable" });

    const throwing = makePi();
    throwing.appendEntry.mockImplementation(() => { throw new Error("disk unavailable"); });
    projection.bindApi(throwing);
    expect(projection.recordDurableTranscriptEvent(event)).toEqual({ status: "failed" });
    expect(projection.getTranscriptEventsForTest()).toEqual([]);
  });

  test("a stale writer is evicted and a fresh replacement records successfully", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    const stale = makePi();
    stale.appendEntry.mockImplementation(() => {
      throw new Error("This extension ctx is stale after session replacement or reload");
    });
    projection.bindApi(stale);

    expect(projection.recordDurableTranscriptEvent(durableUser("stale-event"))).toEqual({ status: "failed" });
    expect(projection.recordDurableTranscriptEvent(durableUser("still-stale"))).toEqual({ status: "unavailable" });
    expect(stale.appendEntry).toHaveBeenCalledOnce();

    const fresh = makePi();
    projection.bindReplacementContext({
      ...fresh,
      sessionManager: { getSessionId: () => "session-2" },
    } as never);
    const event = { ...durableUser("fresh-event"), sessionId: "session-2" };
    expect(projection.recordDurableTranscriptEvent(event)).toEqual({ status: "recorded" });
    expect(fresh.appendEntry).toHaveBeenCalledWith(TRANSCRIPT_EVENT_CUSTOM_TYPE, event);
  });

  test("shutdown clears only the stale writer and a later bind restores it", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    const first = makePi();
    projection.bindApi(first);
    projection.clearStaleContexts();
    expect(projection.recordDurableTranscriptEvent(durableUser("after-shutdown")))
      .toEqual({ status: "unavailable" });

    const fresh = makePi();
    projection.bindApi(fresh);
    expect(projection.recordDurableTranscriptEvent(durableUser("after-rebind")))
      .toEqual({ status: "recorded" });
    expect(first.appendEntry).not.toHaveBeenCalled();
    expect(fresh.appendEntry).toHaveBeenCalledOnce();
  });

  test("the compatibility append path remains explicitly non-durable", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    const pi = makePi();
    projection.bindApi(pi);
    projection.appendTranscriptEvent(durableUser("fallback-event"));

    expect(pi.appendEntry).not.toHaveBeenCalled();
    expect(projection.getTranscriptEventsForTest()).toEqual([durableUser("fallback-event")]);
  });
});

describe("SdkSessionProjection mesh ingress batching", () => {
  test("delivers messages arriving mid-run exactly once as one batch after settle", async () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    const pi = makePi();
    projection.bindApi(pi);
    projection.markAgentRunStarted();

    expect(projection.enqueueMeshMessage("/repo@reviewer", "mesh-message-1")).toEqual({ accepted: true });
    expect(projection.enqueueMeshMessage("/repo@worker", "mesh-message-2")).toEqual({ accepted: true });
    await Promise.resolve();
    expect(pi.sendMessage).not.toHaveBeenCalled();

    projection.markAgentSettled();
    await Promise.resolve();

    expect(pi.sendMessage).toHaveBeenCalledOnce();
    expect(pi.sendMessage).toHaveBeenCalledWith(
      expect.objectContaining({
        customType: "outpost-pi:mesh-message",
        content: expect.stringMatching(/mesh-message-1[\s\S]*mesh-message-2/),
        display: true,
      }),
      { triggerTurn: true, deliverAs: "followUp" },
    );

    projection.markAgentSettled();
    await Promise.resolve();
    expect(pi.sendMessage).toHaveBeenCalledOnce();
  });

  test("enforces per-peer frame and global byte admission without evicting accepted messages", async () => {
    const projection = new SdkSessionProjection({
      outputs: makeOutputs(),
      meshIngressLimits: {
        maxFrames: 3,
        maxBytes: 12,
        maxFramesPerPeer: 2,
        maxBytesPerPeer: 8,
      },
    });
    projection.markAgentRunStarted();

    expect(projection.enqueueMeshMessage("peer-a", "1234")).toEqual({ accepted: true });
    expect(projection.enqueueMeshMessage("peer-a", "5678")).toEqual({ accepted: true });
    expect(projection.enqueueMeshMessage("peer-a", "x")).toEqual({ accepted: false, reason: "frame_limit" });
    expect(projection.enqueueMeshMessage("peer-b", "12345")).toEqual({ accepted: false, reason: "byte_limit" });

    const pi = makePi();
    projection.bindApi(pi);
    projection.markAgentSettled();
    await Promise.resolve();
    expect(pi.sendMessage).toHaveBeenCalledWith(
      expect.objectContaining({ content: expect.stringMatching(/1234[\s\S]*5678/) }),
      expect.anything(),
    );
    const delivered = String(pi.sendMessage.mock.calls[0]![0].content);
    expect(delivered).not.toContain("12345");
    expect(delivered).not.toContain("\nx\n");
  });

  test("restores a batch after a synchronous SDK throw and redelivers it at the next settle", async () => {
    const outputs = { ...makeOutputs(), onMeshDeliveryFailure: vi.fn() };
    const projection = new SdkSessionProjection({ outputs });
    const pi = makePi();
    pi.sendMessage
      .mockImplementationOnce(() => { throw new Error("handoff failed"); })
      .mockImplementationOnce(() => undefined);
    projection.bindApi(pi);
    projection.markAgentRunStarted();
    expect(projection.enqueueMeshMessage("peer-a", "restore-sync")).toEqual({ accepted: true });

    projection.markAgentSettled();
    await Promise.resolve();
    expect(outputs.onMeshDeliveryFailure).toHaveBeenCalledWith("send_failed");

    projection.markAgentSettled();
    await Promise.resolve();
    expect(pi.sendMessage).toHaveBeenCalledTimes(2);
    expect(pi.sendMessage.mock.calls[1]![0]).toMatchObject({ content: "restore-sync" });

    projection.markAgentSettled();
    await Promise.resolve();
    expect(pi.sendMessage).toHaveBeenCalledTimes(2);
  });

  test("restores a batch after an asynchronous SDK rejection and redelivers it at the next settle", async () => {
    const outputs = { ...makeOutputs(), onMeshDeliveryFailure: vi.fn() };
    const projection = new SdkSessionProjection({ outputs });
    const failedHandoff = deferred<void>();
    const pi = makePi();
    pi.sendMessage
      .mockImplementationOnce(() => failedHandoff.promise)
      .mockImplementationOnce(() => undefined);
    projection.bindApi(pi);
    projection.markAgentRunStarted();
    expect(projection.enqueueMeshMessage("peer-a", "restore-async")).toEqual({ accepted: true });

    projection.markAgentSettled();
    await Promise.resolve();
    failedHandoff.reject(new Error("async handoff failed"));
    await vi.waitFor(() => expect(outputs.onMeshDeliveryFailure).toHaveBeenCalledWith("send_failed"));

    projection.markAgentSettled();
    await Promise.resolve();
    expect(pi.sendMessage).toHaveBeenCalledTimes(2);
    expect(pi.sendMessage.mock.calls[1]![0]).toMatchObject({ content: "restore-async" });
  });

  test("evicts a stale-context rejected batch without redelivery on a fresh binding", async () => {
    const outputs = { ...makeOutputs(), onMeshDeliveryFailure: vi.fn() };
    const projection = new SdkSessionProjection({ outputs });
    const stale = makePi();
    stale.sendMessage.mockRejectedValue(
      new Error("This extension ctx is stale after session replacement or reload"),
    );
    projection.bindApi(stale);
    projection.markAgentRunStarted();
    expect(projection.enqueueMeshMessage("peer-a", "stale-rejected")).toEqual({ accepted: true });

    projection.markAgentSettled();
    await vi.waitFor(() => expect(outputs.onMeshDeliveryFailure).toHaveBeenCalledWith("stale_session"));
    expect(projection.messageApiBinding()).toBeNull();

    const fresh = makePi();
    projection.bindApi(fresh);
    projection.markAgentSettled();
    await Promise.resolve();
    expect(fresh.sendMessage).not.toHaveBeenCalled();
  });

  test("keeps failed batches in frame and byte admission accounting until redelivery", async () => {
    const projection = new SdkSessionProjection({
      outputs: makeOutputs(),
      meshIngressLimits: {
        maxFrames: 2,
        maxBytes: 4,
        maxFramesPerPeer: 1,
        maxBytesPerPeer: 4,
      },
    });
    const pi = makePi();
    pi.sendMessage
      .mockImplementationOnce(() => { throw new Error("handoff failed"); })
      .mockImplementationOnce(() => undefined);
    projection.bindApi(pi);
    projection.markAgentRunStarted();
    expect(projection.enqueueMeshMessage("peer-a", "1234")).toEqual({ accepted: true });

    projection.markAgentSettled();
    await Promise.resolve();
    expect(projection.enqueueMeshMessage("peer-a", "")).toEqual({ accepted: false, reason: "frame_limit" });
    expect(projection.enqueueMeshMessage("peer-b", "x")).toEqual({ accepted: false, reason: "byte_limit" });

    projection.markAgentSettled();
    await Promise.resolve();
    expect(pi.sendMessage).toHaveBeenCalledTimes(2);
    expect(pi.sendMessage.mock.calls[1]![0]).toMatchObject({ content: "1234" });
  });

  test("suppresses a scheduled flush after session replacement invalidates its generation", async () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    const pi = makePi();
    projection.bindApi(pi);
    projection.markAgentRunStarted();
    expect(projection.enqueueMeshMessage("peer-a", "stale-session-message")).toEqual({ accepted: true });

    projection.markAgentSettled();
    projection.clearStaleContexts();
    await Promise.resolve();

    expect(pi.sendMessage).not.toHaveBeenCalled();
  });
});

describe("SdkSessionProjection queued-message delivery rejection policy", () => {
  test("observes an asynchronous rejection after clearing the queue", async () => {
    const outputs = makeOutputs();
    const projection = new SdkSessionProjection({ outputs });
    const rejection = new Error("queued delivery failed");
    const deliver = vi.fn(() => Promise.reject(rejection));
    const onRejected = vi.fn();

    projection.applyTurn({ type: "queued_message_set", id: "queued-1", text: "deferred" });
    projection.maybeDrainQueuedMessage(deliver, onRejected);

    expect(projection.turnProjection()).toMatchObject({ phase: "idle", queuedMessage: null });
    expect(outputs.broadcast).toHaveBeenCalledTimes(1);
    const delivered = deliver.mock.calls[0]![0];
    await vi.waitFor(() => expect(onRejected).toHaveBeenCalledOnce());
    expect(onRejected).toHaveBeenCalledWith(delivered, rejection);
  });

  test("preserves synchronous delivery throws for the owning event handler", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    const rejection = new Error("synchronous queued delivery failure");
    const onRejected = vi.fn();

    projection.applyTurn({ type: "queued_message_set", id: "queued-2", text: "deferred" });
    expect(() => projection.maybeDrainQueuedMessage(() => { throw rejection; }, onRejected)).toThrow(rejection);
    expect(projection.turnProjection()).toMatchObject({ phase: "idle", queuedMessage: null });
    expect(onRejected).not.toHaveBeenCalled();
  });
});

/**
 * Regression: a stale-ctx failure in `wakeAgent` (and the null-`messageApi`
 * window after a replacement) must be RECOVERABLE, not a permanent
 * `internal_error`. The phone should tolerate it — a sibling pi may have
 * handled the message (cross-process fanout to the same owner_pk+room), or
 * the next session_start rebinds a working api and the phone retries. Real
 * delivery failures stay non-recoverable so they still surface.
 */
describe("SdkSessionProjection wakeAgent recoverable failures", () => {
  const STALE_MSG =
    "This extension ctx is stale after session replacement or reload";

  function makeStalePi() {
    return {
      sendMessage: vi.fn(),
      sendUserMessage: vi.fn(() => { throw new Error(STALE_MSG); }),
    };
  }

  test("a stale sendUserMessage returns recoverable (not a permanent failure)", async () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makeStalePi());

    const result = await projection.wakeAgent({ type: "text", text: "hi" });
    expect(result.ok).toBe(false);
    expect(result.recoverable).toBe(true);
    expect(result.detail).toContain("stale");
    // The stale binding was forgotten so a later wake doesn't reuse it.
    expect(projection.messageApiBinding()).toBeNull();
  });

  test("a null messageApi (post-replacement window) returns recoverable", async () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    // No bindApi — messageApi is null, the immediate-after-replacement window.
    const result = await projection.wakeAgent({ type: "text", text: "hi" });
    expect(result.ok).toBe(false);
    expect(result.recoverable).toBe(true);
    expect(result.detail).toBe("agent session not bound yet");
  });

  test("a non-stale delivery failure stays non-recoverable (still surfaces)", async () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi({
      sendMessage: vi.fn(),
      sendUserMessage: vi.fn(() => { throw new Error("malformed content"); }),
    });
    const result = await projection.wakeAgent({ type: "text", text: "hi" });
    expect(result.ok).toBe(false);
    expect(result.recoverable).toBe(false);
    expect(result.detail).toBe("malformed content");
  });

  test("a successful wake is not recoverable", async () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi({
      sendMessage: vi.fn(),
      sendUserMessage: vi.fn(async () => {}),
    });
    const result = await projection.wakeAgent({ type: "text", text: "hi" });
    expect(result.ok).toBe(true);
    expect(result.recoverable).toBeUndefined();
  });
});

/**
 * Regression: an inbound app action routed through `freshActionCtx()` must NOT
 * crash pi when the captured event/command ctx is stale after a session
 * replacement or `/reload`.
 *
 * The SDK marks a replaced ctx's guarded getters (modelRegistry, ui, cwd,
 * compact, newSession, getModel, …) to throw a stale-context error via
 * `assertActive()`. `wrapActionCtx` previously accessed those getters OUTSIDE
 * its per-method try/catch (e.g. `if (ctx.modelRegistry) …`), so a stale ctx
 * threw synchronously and propagated uncaught through the relay message
 * router, taking down the whole pi process. The fix wraps the whole
 * property-access sequence and returns null on a stale ctx so callers degrade
 * to a graceful `action_error` instead of crashing.
 */
describe("SdkSessionProjection stale-ctx crash guard on freshActionCtx", () => {
  const STALE_MSG =
    "This extension ctx is stale after session replacement or reload.";

  /** A ctx whose every guarded getter throws the stale-context error, mirroring
   *  a real SDK ctx after `runner.markStale()`. */
  function makeStaleCtx(): Record<string, unknown> {
    const throwStale = (): never => { throw new Error(STALE_MSG); };
    // `typeof ctx.X === "function"` triggers the getter, so model it as a
    // throwing function property too.
    return {
      get compact() { throwStale(); },
      get newSession() { throwStale(); },
      get getModel() { throwStale(); },
      get modelRegistry() { throwStale(); },
      get ui() { throwStale(); },
      get cwd() { throwStale(); },
      get abort() { throwStale(); },
    };
  }

  test("freshActionCtx on a stale event ctx returns null instead of throwing", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());
    // Arm a stale event ctx directly (simulates a post-replacement window
    // before clearStaleContexts / the next session_start rebinds it).
    (projection as unknown as { eventCtx: unknown }).eventCtx = makeStaleCtx();

    expect(() => projection.freshActionCtx()).not.toThrow();
    expect(projection.freshActionCtx()).toBeNull();
  });

  test("freshCommandActionCtx on a stale command ctx returns null instead of throwing", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());
    (projection as unknown as { commandCtx: unknown }).commandCtx = makeStaleCtx();

    expect(() => projection.freshCommandActionCtx()).not.toThrow();
    expect(projection.freshCommandActionCtx()).toBeNull();
  });

  test("a non-stale error from the getters still propagates (guard is stale-specific)", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());
    const otherErr = new Error("some unrelated getter failure");
    (projection as unknown as { eventCtx: unknown }).eventCtx = {
      get modelRegistry() { throw otherErr; },
      get compact() { throw otherErr; },
      get newSession() { throw otherErr; },
      get getModel() { throw otherErr; },
    };

    expect(() => projection.freshActionCtx()).toThrow(otherErr);
  });
});

/**
 * Regression: a `/resume`-style `session_start` must backfill the transcript
 * log from the persisted session manager so `session_sync` can replay history
 * that predates this extension instance.
 *
 * The SDK's `/resume` loads persisted entries into a fresh `SessionManager` and
 * renders them DIRECTLY to the TUI from `buildContextEntries()` — bypassing the
 * agent message pipeline, so `message_end` never fires for resumed history.
 * Without backfill, `TranscriptEventLog` stays empty and `session_sync` returns
 * a blank `session_history` even though the TUI shows full history.
 */
describe("SdkSessionProjection resume backfill", () => {
  type ResumableCtx = ReturnType<typeof makeSessionStartCtx> & {
    sessionManager: {
      getSessionId: () => string;
      buildContextEntries: () => SdkTranscriptContextEntry[];
    };
  };

  function makeResumedCtx(
    sessionId: string,
    messages: LegacyAgentMessage[],
    extraEntries: SdkTranscriptContextEntry[] = [],
  ): ResumableCtx {
    return {
      ...makeSessionStartCtx(),
      sessionManager: {
        getSessionId: () => sessionId,
        buildContextEntries: () => [
          ...messages.map((message) => ({ type: "message" as const, message })),
          ...extraEntries,
        ],
      },
    };
  }

  const persistedHistory: LegacyAgentMessage[] = [
    { role: "user", content: "hello from the earlier session", timestamp: 1_000 },
    { role: "assistant", content: [{ type: "text", text: "hi back" }], timestamp: 1_001 },
    {
      role: "toolResult",
      toolCallId: "call-1",
      content: "[{ type: 'text', text: '42' }]",
      timestamp: 1_002,
    },
  ];

  test("session_sync after a resume-style session_start replays persisted entries", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());

    projection.bindSessionContext(makeResumedCtx("resumed-session-1", persistedHistory));

    const history = projection.buildSessionHistoryMessage("req-1", undefined);
    expect(history.events.map((e) => e.type)).toEqual([
      "user_input",
      "agent_message",
      "tool_result",
    ]);
    expect(history.events[0]).toMatchObject({ text: "hello from the earlier session" });
  });

  test("backfill stamps events with the fresh session id, not a stale prior id", () => {
    // Simulate a prior session id still held by the issuer (clearStaleContexts
    // does not clear it). The backfill must use the NEW resumed id, otherwise
    // forSession(currentId) would filter the events out → blank history.
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());
    // First session captures id "prior-session".
    projection.bindSessionContext(makeResumedCtx("prior-session", []));
    // Resume into a new session with persisted history.
    projection.bindSessionContext(makeResumedCtx("resumed-session-2", persistedHistory));

    const history = projection.buildSessionHistoryMessage("req-2", undefined);
    expect(history.session_id).toBe("resumed-session-2");
    expect(history.events.map((e) => e.type)).toEqual([
      "user_input",
      "agent_message",
      "tool_result",
    ]);
  });

  test("backfill is idempotent across a reload of the same session (no duplicates)", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());
    const ctx = makeResumedCtx("same-session", persistedHistory);

    projection.bindSessionContext(ctx);
    projection.bindSessionContext(ctx); // reload re-fires session_start

    const history = projection.buildSessionHistoryMessage("req-3", undefined);
    // Three persisted entries, not six — deduped by eventId.
    expect(history.events).toHaveLength(3);
  });

  test("a session_start with no persisted history backfills nothing", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());
    projection.bindSessionContext(makeResumedCtx("fresh-session", []));

    const history = projection.buildSessionHistoryMessage("req-4", undefined);
    expect(history.events).toEqual([]);
  });

  test("backfill does not duplicate a user prompt already captured live from the app", () => {
    // Review finding: a live app-origin user_message is stamped with the APP's
    // clientMessageId, while the backfill maps the same persisted user message
    // to a synthetic `sync_${ts}` id. eventId-only dedupe would NOT collapse
    // them, and the projection dedupes by clientMessageId — so the phone would
    // show the same prompt twice after a /reload. The backfill must reuse the
    // existing live event's clientMessageId/eventId (content-aware dedupe).
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());
    projection.bindSessionContext(makeResumedCtx("live-session", []));

    // App delivered a user message live (same content as a persisted one).
    projection.appendUserConfirmedTranscriptEvent({
      sessionId: "live-session",
      ts: 5_000,
      clientMessageId: "app-msg-1",
      text: "hello from the earlier session",
    });

    // Reload-style session_start re-runs the backfill over the live log, with
    // the same persisted user prompt present.
    projection.bindSessionContext(
      makeResumedCtx("live-session", [
        { role: "user", content: "hello from the earlier session", timestamp: 1_000 },
        { role: "assistant", content: [{ type: "text", text: "hi back" }], timestamp: 1_001 },
      ]),
    );

    const history = projection.buildSessionHistoryMessage("req-5", undefined);
    // One user_input (the live app event), not two.
    const userInputs = history.events.filter((e) => e.type === "user_input");
    expect(userInputs).toHaveLength(1);
    expect(userInputs[0]).toMatchObject({ id: "app-msg-1" });
  });

  test("backfill replays a raw active-branch compaction entry", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());
    projection.bindSessionContext({
      ...makeSessionStartCtx(),
      sessionManager: {
        getSessionId: () => "compacted-session",
        buildContextEntries: () => [
          { type: "message", message: { role: "user", content: "old prompt", timestamp: 100 } },
          {
            type: "compaction",
            summary: "prior context was compacted",
            tokensBefore: 5000,
            timestamp: new Date(200).toISOString(),
          },
          {
            type: "message",
            message: { role: "assistant", content: [{ type: "text", text: "post-compact reply" }], timestamp: 300 },
          },
        ],
      },
    } as never);

    const history = projection.buildSessionHistoryMessage("req-6", undefined);
    expect(history.events.map((e) => e.type)).toEqual([
      "user_input",
      "compaction",
      "agent_message",
    ]);
    expect(history.events[1]).toMatchObject({ summary: "prior context was compacted", tokens_before: 5000 });
  });

  test("a /new after backfill returns empty history for the new session", () => {
    // resetSessionForNew clears the transcript log and broadcasts an empty
    // session_history. A prior backfill must not bleed into the new session.
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());
    projection.bindSessionContext(makeResumedCtx("old-session", persistedHistory));
    expect(projection.buildSessionHistoryMessage("before", undefined).events).toHaveLength(3);

    projection.resetSessionForNew("new-ack");

    expect(projection.buildSessionHistoryMessage("after", undefined).events).toEqual([]);
  });
});

describe("SdkSessionProjection user_message ingress idempotency guard", () => {
  // story-extension-user-message-ingress-idempotency: a duplicate
  // user_message frame (reconnect flush, relay fan-out, app re-send) must
  // not re-invoke the agent. The guard is a clientMessageId-keyed Set per
  // session, cleared on session replacement.
  test("wasUserMessageDelivered is false before recording, true after", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());
    projection.bindSessionContext(makeSessionStartCtx());
    const sessionId = projection.currentRemoteSessionId();
    expect(projection.wasUserMessageDelivered(sessionId, "msg-1")).toBe(false);
    projection.recordDeliveredUserMessageId(sessionId, "msg-1");
    expect(projection.wasUserMessageDelivered(sessionId, "msg-1")).toBe(true);
    // A different id is still undelivered.
    expect(projection.wasUserMessageDelivered(sessionId, "msg-2")).toBe(false);
  });

  test("the guard is session-scoped — a different session is not suppressed", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());
    projection.bindSessionContext(makeSessionStartCtx());
    const sessionId = projection.currentRemoteSessionId();
    projection.recordDeliveredUserMessageId(sessionId, "msg-1");
    expect(projection.wasUserMessageDelivered(sessionId, "msg-1")).toBe(true);
    // A different session (e.g. after /new) must not see the prior session's ids.
    expect(projection.wasUserMessageDelivered("other-session", "msg-1")).toBe(false);
  });

  test("resetSessionForNew clears the delivered-id set (no false suppression after /new)", () => {
    const projection = new SdkSessionProjection({ outputs: makeOutputs() });
    projection.bindApi(makePi());
    projection.bindSessionContext(makeSessionStartCtx());
    const sessionId = projection.currentRemoteSessionId();
    projection.recordDeliveredUserMessageId(sessionId, "msg-1");
    expect(projection.wasUserMessageDelivered(sessionId, "msg-1")).toBe(true);

    projection.resetSessionForNew("new-ack");

    // After /new, the set is cleared. A fresh send with the same id (unlikely
    // — the app generates fresh ids — but defensive) is not falsely suppressed.
    expect(projection.wasUserMessageDelivered(sessionId, "msg-1")).toBe(false);
  });
});

describe("SdkSessionProjection delivered-user reservations", () => {
  function liveUserInputs(outputs: ReturnType<typeof makeOutputs>) {
    return (outputs.broadcast as ReturnType<typeof vi.fn>).mock.calls
      .map((call) => call[0])
      .filter((message) => message?.type === "user_input");
  }

  test("cancelling one equal-content reservation removes only that entry", () => {
    const outputs = makeOutputs();
    const projection = new SdkSessionProjection({ outputs });
    const cancelFirst = projection.rememberDeliveredUserEvent(
      "same prompt",
      undefined,
      "cli_first",
      "event-first",
    );
    projection.rememberDeliveredUserEvent("same prompt", undefined, "cli_second", "event-second");

    cancelFirst();
    projection.appendLegacySdkMessageToTranscript({
      role: "user",
      content: "same prompt",
      timestamp: 6_000,
    });

    expect(liveUserInputs(outputs)).toEqual([
      expect.objectContaining({ id: "cli_second", ts: 6_000 }),
    ]);
    expect(projection.getTranscriptEventsForTest()).toContainEqual(
      expect.objectContaining({ eventId: "event-second", clientMessageId: "cli_second" }),
    );
  });

  test("cancelling after consumption is a no-op for a later equal-content reservation", () => {
    const outputs = makeOutputs();
    const projection = new SdkSessionProjection({ outputs });
    const cancelConsumed = projection.rememberDeliveredUserEvent(
      "repeated prompt",
      undefined,
      "cli_consumed",
      "event-consumed",
    );
    projection.appendLegacySdkMessageToTranscript({
      role: "user",
      content: "repeated prompt",
      timestamp: 7_000,
    });
    projection.rememberDeliveredUserEvent(
      "repeated prompt",
      undefined,
      "cli_later",
      "event-later",
    );

    cancelConsumed();
    projection.appendLegacySdkMessageToTranscript({
      role: "user",
      content: "repeated prompt",
      timestamp: 7_001,
    });

    expect(liveUserInputs(outputs).map((message) => message.id)).toEqual([
      "cli_consumed",
      "cli_later",
    ]);
  });

  test("equal-content sibling reservations retain FIFO order", () => {
    const outputs = makeOutputs();
    const projection = new SdkSessionProjection({ outputs });
    projection.rememberDeliveredUserEvent("fifo prompt", undefined, "cli_fifo_1", "event-fifo-1");
    projection.rememberDeliveredUserEvent("fifo prompt", undefined, "cli_fifo_2", "event-fifo-2");

    projection.appendLegacySdkMessageToTranscript({ role: "user", content: "fifo prompt", timestamp: 8_000 });
    projection.appendLegacySdkMessageToTranscript({ role: "user", content: "fifo prompt", timestamp: 8_001 });

    expect(liveUserInputs(outputs).map((message) => message.id)).toEqual(["cli_fifo_1", "cli_fifo_2"]);
    expect(projection.getTranscriptEventsForTest().map((event) => event.eventId)).toEqual([
      "event-fifo-1",
      "event-fifo-2",
    ]);
  });

  test("session reset clears every unconsumed reservation", () => {
    const outputs = makeOutputs();
    const projection = new SdkSessionProjection({ outputs });
    projection.rememberDeliveredUserEvent("old prompt", undefined, "cli_old", "event-old");

    projection.resetSessionForNew("new-session-request");
    projection.appendLegacySdkMessageToTranscript({
      role: "user",
      content: "old prompt",
      timestamp: 9_000,
    });

    expect(liveUserInputs(outputs)).toEqual([
      expect.objectContaining({ id: "sync_9000", ts: 9_000 }),
    ]);
  });
});

// Regression for `story-mobile-assistant-message-duplicated-live-replay`
// decision 1 (identity source (a)). The extension's `message_end`-driven
// `appendLegacySdkMessageToTranscript` must broadcast a live `agent_message`
// carrying the stable (ts, message_id) so the app's live commit path derives
// the SAME deterministic identity as session_history replay.
describe("SdkSessionProjection live assistant identity (decision 1)", () => {
  function makeCtx(sessionId: string): ReturnType<typeof makeSessionStartCtx> & {
    sessionManager: { getSessionId: () => string; buildContextEntries: () => never[] };
  } {
    return {
      ...makeSessionStartCtx(),
      sessionManager: {
        getSessionId: () => sessionId,
        buildContextEntries: () => [],
      },
    };
  }

  test("appendLegacySdkMessageToTranscript broadcasts a live agent_message with stable ts + message_id", () => {
    const outputs = makeOutputs();
    const projection = new SdkSessionProjection({ outputs });
    projection.bindApi(makePi());
    projection.bindSessionContext(makeCtx("session-identity-1"));

    // First, a user message so lastTranscriptUserId is set (replyTo target).
    projection.appendLegacySdkMessageToTranscript({
      role: "user",
      content: "hello",
      timestamp: 1_000,
    });
    // Then an assistant message with one text block at ts 1_001.
    projection.appendLegacySdkMessageToTranscript({
      role: "assistant",
      content: [{ type: "text", text: "hi back" }],
      timestamp: 1_001,
    });

    // The live broadcast must carry ts + message_id matching the replay path.
    const agentMessages = (outputs.broadcast as ReturnType<typeof vi.fn>).mock.calls
      .map((c) => c[0])
      .filter((m) => m?.type === "agent_message");
    expect(agentMessages).toHaveLength(1);
    const live = agentMessages[0];
    expect(live.ts).toBe(1_001);
    expect(live.message_id).toBe("sync_1001:assistant:0");
    expect(live.text).toBe("hi back");

    // The replay path (session_history) must emit the SAME (ts, text,
    // message_id) for the app to derive a matching deterministic eventId —
    // including the block-unique message_id so multi-block assistant messages
    // do not collide.
    const history = projection.buildSessionHistoryMessage("req-1", undefined);
    const replayAgent = history.events.find((e) => e.type === "agent_message");
    expect(replayAgent).toBeDefined();
    expect(replayAgent?.ts).toBe(1_001);
    expect(replayAgent?.text).toBe("hi back");
    expect(replayAgent?.message_id).toBe("sync_1001:assistant:0");
  });

  test("appendLegacySdkMessageToTranscript broadcasts a live user_input with stable ts (user-message follow-up)", () => {
    const outputs = makeOutputs();
    const projection = new SdkSessionProjection({ outputs });
    projection.bindApi(makePi());
    projection.bindSessionContext(makeCtx("session-identity-2"));

    // A user message at ts 5_000.
    projection.appendLegacySdkMessageToTranscript({
      role: "user",
      content: "hello from phone",
      timestamp: 5_000,
    });

    // The live broadcast must carry ts matching the replay path so the app
    // can derive the same deterministic eventId (server:<sid>:user_input:
    // <id>:<ts>). For an unmatched (foreign) user message, clientMessageId
    // is sync_<ts>.
    const userInputs = (outputs.broadcast as ReturnType<typeof vi.fn>).mock.calls
      .map((c) => c[0])
      .filter((m) => m?.type === "user_input");
    expect(userInputs).toHaveLength(1);
    const live = userInputs[0];
    expect(live.ts).toBe(5_000);
    expect(live.text).toBe("hello from phone");
    expect(live.id).toBe("sync_5000");

    // The replay path must emit the SAME (ts, id) for the app to derive a
    // matching deterministic eventId.
    const history = projection.buildSessionHistoryMessage("req-1", undefined);
    const replayUser = history.events.find((e) => e.type === "user_input");
    expect(replayUser).toBeDefined();
    expect(replayUser?.ts).toBe(5_000);
    expect(replayUser?.id).toBe("sync_5000");
    expect(replayUser?.text).toBe("hello from phone");
  });
});

describe("SdkSessionProjection delivery-path debug events", () => {
  function makeProjectionWithDebug() {
    const fake = new FakeDeliveryDebugLog();
    const outputs = { ...makeOutputs(), deliveryDebugLog: fake };
    const projection = new SdkSessionProjection({ outputs });
    return { projection, fake };
  }

  test("bindApi emits message_api_armed { via: factory }", () => {
    const { projection, fake } = makeProjectionWithDebug();
    projection.bindApi(makePi() as never);
    const armed = fake.byTag("message_api_armed");
    expect(armed).toHaveLength(1);
    expect(armed[0]).toMatchObject({ tag: "message_api_armed", via: "factory" });
  });

  test("clearStaleContexts emits message_api_null { reason: shutdown } + command_ctx { armed: false }", () => {
    const { projection, fake } = makeProjectionWithDebug();
    projection.clearStaleContexts();
    expect(fake.byTag("message_api_null")).toHaveLength(1);
    expect(fake.byTag("message_api_null")[0]).toMatchObject({ reason: "shutdown" });
    expect(fake.byTag("command_ctx")).toHaveLength(1);
    expect(fake.byTag("command_ctx")[0]).toMatchObject({ armed: false });
  });

  test("wakeAgent with null messageApi emits the stuck-null signature (messageApiArmed: false, recoverable)", async () => {
    const { projection, fake } = makeProjectionWithDebug();
    // No bindApi → messageApi is null.
    const result = await projection.wakeAgent("hello" as never);
    expect(result.ok).toBe(false);
    expect(result.recoverable).toBe(true);
    // The projection's wakeAgent does not emit wake_outcome (the caller in
    // index.ts does, where the message id is available). The null state is
    // observable via messageApiBinding() === null — the caller asserts that.
    expect(projection.messageApiBinding()).toBeNull();
    // Sanity: no wake_outcome emitted from the projection itself.
    expect(fake.byTag("wake_outcome")).toHaveLength(0);
  });

  test("wakeAgent with a stale ctx forgets the api and emits message_api_null { reason: stale }", async () => {
    const { projection, fake } = makeProjectionWithDebug();
    const pi = makePi();
    pi.sendUserMessage.mockRejectedValueOnce(new Error("This extension ctx is stale after session replacement or reload"));
    projection.bindApi(pi as never);
    const result = await projection.wakeAgent("hello" as never);
    expect(result.ok).toBe(false);
    expect(result.recoverable).toBe(true);
    expect(projection.messageApiBinding()).toBeNull();
    expect(fake.byTag("message_api_null")).toHaveLength(1);
    expect(fake.byTag("message_api_null")[0]).toMatchObject({ reason: "stale" });
  });

  test("bindCommandContext emits command_ctx { armed: true, via: slash }", () => {
    const { projection, fake } = makeProjectionWithDebug();
    projection.bindCommandContext({} as never);
    const ctx = fake.byTag("command_ctx");
    expect(ctx).toHaveLength(1);
    expect(ctx[0]).toMatchObject({ armed: true, via: "slash" });
  });

  test("bindReplacementContext emits message_api_armed { via: withSession } + command_ctx { via: withSession }", () => {
    const { projection, fake } = makeProjectionWithDebug();
    // bindReplacementContext is the mobile session_new (withSession) re-arm
    // path — distinct from the factory /reload re-arm in bindApi. The story
    // needs this evidence to prove mobile recovery.
    projection.setSessionIdForTest("session-withsession-1234");
    projection.bindReplacementContext({
      sendUserMessage: vi.fn(),
      sendMessage: vi.fn(),
      sessionManager: { getSessionId: () => "session-withsession-1234" },
    } as never);
    const armed = fake.byTag("message_api_armed");
    expect(armed).toHaveLength(1);
    expect(armed[0]).toMatchObject({ tag: "message_api_armed", via: "withSession" });
    const ctx = fake.byTag("command_ctx");
    expect(ctx).toHaveLength(1);
    expect(ctx[0]).toMatchObject({ armed: true, via: "withSession" });
  });
});

describe("SdkSessionProjection resetTurnSnapshot converges working on shutdown", () => {
  // Regression: the SDK session_shutdown handler must publish working=false
  // and reset the turn for the successor. If an active turn is abandoned by a
  // replacement (old runner invalidated, terminal agent_end/turn_end events
  // dropped on the stale runner), the only convergence point is
  // resetTurnSnapshot() called from disposeRuntimePorts before relay.stop().
  // Without it the app's working indicator stays stuck true.
  test("resetTurnSnapshot on an active turn publishes working=false and converges idle", () => {
    const outputs = makeOutputs();
    const projection = new SdkSessionProjection({ outputs });
    projection.setSessionIdForTest("session-shutdown-turn");
    // Seed an active turn (working=true) and confirm the working=true publish.
    projection.applyTurn({ type: "turn_start", fallbackTurnId: "turn-active" });
    expect(outputs.publishRoomMeta).toHaveBeenCalledWith({ working: true });
    expect(projection.turnProjection().working).toBe(true);

    // resetTurnSnapshot is the shutdown convergence point: it must publish
    // working=false (the true→false edge) while the relay is still connected,
    // and leave the projection idle for the successor session.
    outputs.publishRoomMeta.mockClear();
    projection.resetTurnSnapshot();
    expect(outputs.publishRoomMeta).toHaveBeenCalledWith({ working: false });
    expect(projection.turnProjection()).toMatchObject({
      working: false,
      activeTurnId: null,
      phase: "idle",
    });
  });

  test("resetTurnSnapshot on an already-idle projection does not republish working", () => {
    const outputs = makeOutputs();
    const projection = new SdkSessionProjection({ outputs });
    projection.setSessionIdForTest("session-shutdown-idle");
    // No turn seeded — projection starts idle.
    outputs.publishRoomMeta.mockClear();
    projection.resetTurnSnapshot();
    // No working edge to cross (false→false); must not spam a redundant frame.
    expect(outputs.publishRoomMeta).not.toHaveBeenCalled();
    expect(projection.turnProjection().working).toBe(false);
  });
});

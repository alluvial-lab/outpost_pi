import { describe, expect, test } from "vitest";
import type { TranscriptEvent } from "./transcript_event.js";
import {
  TRANSCRIPT_EVENT_CUSTOM_TYPE,
  encodeDurableTranscriptEventV1,
} from "./durable_transcript_event.js";
import {
  deterministicTranscriptEventId,
  reconcileTranscriptContextEntries,
  projectSessionHistory,
  stringifyToolResult,
  type SdkTranscriptContextEntry,
} from "./transcript_projection.js";

const sessionId = "sess-a";

function user(clientMessageId: string, text: string, ts: number): TranscriptEvent {
  return {
    kind: "user_confirmed",
    eventId: deterministicTranscriptEventId(sessionId, "user_confirmed", clientMessageId),
    sessionId,
    ts,
    clientMessageId,
    text,
  };
}

function durableEntry(event: TranscriptEvent, customType = TRANSCRIPT_EVENT_CUSTOM_TYPE): SdkTranscriptContextEntry {
  return { type: "custom", customType, data: encodeDurableTranscriptEventV1(event) };
}

function assistant(replyTo: string, text: string, ts: number): TranscriptEvent {
  return {
    kind: "assistant_committed",
    eventId: deterministicTranscriptEventId(sessionId, "assistant_committed", `msg-${ts}`),
    sessionId,
    ts,
    messageId: `msg-${ts}`,
    replyTo,
    text,
  };
}

describe("transcript session_history projection", () => {
  test("applies limit/truncated after session filtering", () => {
    const events: TranscriptEvent[] = [
      user("u1", "one", 1),
      { ...user("foreign", "skip", 2), sessionId: "other" },
      assistant("u1", "two", 3),
      user("u2", "three", 4),
    ];

    const projection = projectSessionHistory({ sessionId, events, limit: 2 });

    expect(projection.truncated).toBe(true);
    expect(projection.events).toEqual([
      expect.objectContaining({ type: "agent_message", text: "two", ts: 3 }),
      expect.objectContaining({ type: "user_input", text: "three", ts: 4 }),
    ]);
  });

  test("replays image user messages without adding images to text-only messages", () => {
    const projection = projectSessionHistory({
      sessionId,
      limit: 10,
      events: [
        {
          kind: "user_confirmed",
          eventId: deterministicTranscriptEventId(sessionId, "user_confirmed", "img-1"),
          sessionId,
          ts: 10,
          clientMessageId: "img-1",
          text: "what is this?",
          images: [{ data: "QUJD", mime: "image/jpeg" }],
        },
        user("txt-1", "plain", 11),
      ],
    });

    expect(projection.events[0]).toMatchObject({
      type: "user_input",
      id: "img-1",
      text: "what is this?",
      images: [{ data: "QUJD", mime: "image/jpeg" }],
    });
    expect(projection.events[1]).toMatchObject({ type: "user_input", id: "txt-1", text: "plain" });
    expect(projection.events[1]).not.toHaveProperty("images");
  });

  test("replays compaction markers", () => {
    const projection = projectSessionHistory({
      sessionId,
      limit: 10,
      events: [{
        kind: "compaction_recorded",
        eventId: deterministicTranscriptEventId(sessionId, "compaction_recorded", "1700"),
        sessionId,
        ts: 1700,
        summary: "summarised 10 turns",
        tokensBefore: 12345,
      }],
    });

    expect(projection.events).toEqual([
      { ts: 1700, type: "compaction", summary: "summarised 10 turns", tokens_before: 12345 },
    ]);
  });

  test("dedupes deterministic event ids for replay idempotence", () => {
    const event = user("u1", "hello", 1);
    const projection = projectSessionHistory({ sessionId, limit: 10, events: [event, event] });

    expect(projection.events).toHaveLength(1);
    expect(projection.events[0]).toMatchObject({ type: "user_input", id: "u1", text: "hello" });
  });

  test("pre-durable SDK messages remain a mixed-era history fallback", () => {
    const transcriptEvents = reconcileTranscriptContextEntries({
      sessionId,
      entries: [
        { type: "message", message: { role: "user", content: [{ type: "image", data: "QUJD", mimeType: "image/jpeg" }, { type: "text", text: "describe" }], timestamp: 100 } },
        { type: "message", message: { role: "assistant", content: [{ type: "text", text: "running" }, { type: "toolCall", id: "tc_1", name: "bash", arguments: { command: "ls" } }], timestamp: 200, usage: { input: 7, output: 3 } } },
        { type: "message", message: { role: "toolResult", toolCallId: "tc_1", isError: false, content: [{ type: "text", text: "file" }], timestamp: 300 } },
      ],
    });

    expect(transcriptEvents.map((event) => event.kind)).toEqual([
      "user_confirmed",
      "assistant_committed",
      "tool_requested",
      "tool_finished",
    ]);

    const projection = projectSessionHistory({ sessionId, events: transcriptEvents, limit: 10 });
    expect(projection.events).toEqual([
      expect.objectContaining({ type: "user_input", id: "sync_100", text: "describe", images: [{ data: "QUJD", mime: "image/jpeg" }] }),
      expect.objectContaining({ type: "agent_message", in_reply_to: "sync_100", text: "running", usage: { input_tokens: 7, output_tokens: 3 } }),
      expect.objectContaining({ type: "tool_request", tool_call_id: "tc_1", tool: "bash", args: { command: "ls" } }),
      expect.objectContaining({ type: "tool_result", tool_call_id: "tc_1", result: "file" }),
    ]);
  });

  test("durable-era reconciliation is extension-entry authoritative and replay-equivalent", () => {
    const durableEvents: TranscriptEvent[] = [
      user("app-user", "inspect", 101),
      {
        kind: "assistant_committed",
        eventId: deterministicTranscriptEventId(
          sessionId,
          "assistant_committed",
          "sync_200:assistant:0",
        ),
        sessionId,
        ts: 200,
        messageId: "sync_200:assistant:0",
        replyTo: "app-user",
        text: "checking durable state",
        usage: { input_tokens: 7, output_tokens: 3 },
      },
      {
        kind: "tool_requested",
        eventId: "durable-request",
        sessionId,
        ts: 250,
        toolCallId: "call-1",
        tool: "read",
        args: { path: "durable" },
      },
      {
        kind: "tool_finished",
        eventId: "durable-finish",
        sessionId,
        ts: 350,
        toolCallId: "call-1",
        result: "durable result",
      },
    ];
    const entries: SdkTranscriptContextEntry[] = [
      { type: "message", message: { role: "user", content: "inspect", timestamp: 100 } },
      durableEntry(durableEvents[0]!),
      {
        type: "message",
        message: {
          role: "assistant",
          timestamp: 200,
          usage: { input: 99, output: 99 },
          content: [
            { type: "text", text: "competing SDK text" },
            { type: "toolCall", id: "call-1", name: "read", arguments: { path: "sdk" } },
          ],
        },
      },
      durableEntry(durableEvents[1]!),
      durableEntry(durableEvents[2]!),
      {
        type: "message",
        message: { role: "toolResult", toolCallId: "call-1", content: "sdk result", timestamp: 300 },
      },
      durableEntry(durableEvents[3]!),
    ];

    const reopened = reconcileTranscriptContextEntries({ sessionId, entries });
    expect(reopened).toEqual(durableEvents);
    expect(projectSessionHistory({ sessionId, events: reopened, limit: 10 }))
      .toEqual(projectSessionHistory({ sessionId, events: durableEvents, limit: 10 }));
  });

  test("durable tool execution timestamps win while SDK assistant text remains", () => {
    const durableRequest1: TranscriptEvent = {
      kind: "tool_requested",
      eventId: "durable-request-1",
      sessionId,
      ts: 250,
      toolCallId: "tc_1",
      tool: "read",
      args: { path: "a" },
    };
    const durableRequest2: TranscriptEvent = {
      kind: "tool_requested",
      eventId: "durable-request-2",
      sessionId,
      ts: 260,
      toolCallId: "tc_2",
      tool: "read",
      args: { path: "b" },
    };
    const durableFinish: TranscriptEvent = {
      kind: "tool_finished",
      eventId: "durable-finish-1",
      sessionId,
      ts: 350,
      toolCallId: "tc_1",
      result: "durable result",
    };
    const entries: SdkTranscriptContextEntry[] = [
      { type: "message", message: { role: "user", content: "inspect", timestamp: 100 } },
      {
        type: "message",
        message: {
          role: "assistant",
          timestamp: 200,
          content: [
            { type: "text", text: "checking" },
            { type: "toolCall", id: "tc_1", name: "read", arguments: { path: "a" } },
            { type: "toolCall", id: "tc_2", name: "read", arguments: { path: "b" } },
          ],
        },
      },
      durableEntry(durableRequest1),
      durableEntry(durableRequest2),
      { type: "message", message: { role: "toolResult", toolCallId: "tc_1", content: "sdk result", timestamp: 300 } },
      durableEntry(durableFinish),
    ];

    const mapped = reconcileTranscriptContextEntries({ sessionId, entries });
    expect(mapped.map((event) => [event.kind, event.ts])).toEqual([
      ["user_confirmed", 100],
      ["assistant_committed", 200],
      ["tool_requested", 250],
      ["tool_requested", 260],
      ["tool_finished", 350],
    ]);
    expect(mapped.filter((event) => event.kind === "tool_requested").map((event) => event.toolCallId))
      .toEqual(["tc_1", "tc_2"]);
  });

  test("reopens native tool pairs with live-equivalent replay and mixed-era fallback", () => {
    const legacyRequest: SdkTranscriptContextEntry = {
      type: "message",
      message: {
        role: "assistant",
        timestamp: 100,
        content: [{ type: "toolCall", id: "legacy-call", name: "bash", arguments: { command: "pwd" } }],
      },
    };
    const request: TranscriptEvent = {
      kind: "tool_requested",
      eventId: "mesh-request",
      sessionId,
      ts: 200,
      toolCallId: "mesh_envelope-1",
      tool: "agent-network",
      args: { from: "/repo@peer", message: "hello" },
    };
    const finish: TranscriptEvent = {
      kind: "tool_finished",
      eventId: "mesh-finish",
      sessionId,
      ts: 201,
      toolCallId: "mesh_envelope-1",
      result: { from: "/repo@peer", message: "hello" },
    };

    const reopened = reconcileTranscriptContextEntries({
      sessionId,
      entries: [legacyRequest, durableEntry(request), durableEntry(finish)],
    });
    expect(reopened.map((event) => [event.kind, "toolCallId" in event ? event.toolCallId : null]))
      .toEqual([
        ["tool_requested", "legacy-call"],
        ["tool_requested", "mesh_envelope-1"],
        ["tool_finished", "mesh_envelope-1"],
      ]);
    expect(projectSessionHistory({ sessionId, events: reopened, limit: 10 }).events).toEqual([
      { ts: 100, type: "tool_request", tool_call_id: "legacy-call", tool: "bash", args: { command: "pwd" } },
      { ts: 200, type: "tool_request", tool_call_id: "mesh_envelope-1", tool: "agent-network", args: { from: "/repo@peer", message: "hello" } },
      { ts: 201, type: "tool_result", tool_call_id: "mesh_envelope-1", result: { from: "/repo@peer", message: "hello" } },
    ]);
  });

  test("matches repeated equal-content app users FIFO and preserves unmatched SDK history", () => {
    const appUser = (id: string, ts: number): TranscriptEvent => ({
      kind: "user_confirmed",
      eventId: `app-event-${id}`,
      sessionId,
      ts,
      clientMessageId: id,
      text: "repeat",
    });
    const entries: SdkTranscriptContextEntry[] = [
      { type: "message", message: { role: "user", content: "repeat", timestamp: 10 } },
      durableEntry(appUser("app-1", 11)),
      { type: "message", message: { role: "user", content: "repeat", timestamp: 20 } },
      durableEntry(appUser("app-2", 21)),
      { type: "message", message: { role: "user", content: "repeat", timestamp: 30 } },
    ];

    const users = reconcileTranscriptContextEntries({ sessionId, entries })
      .filter((event) => event.kind === "user_confirmed");
    expect(users.map((event) => [event.clientMessageId, event.ts])).toEqual([
      ["app-1", 11],
      ["app-2", 21],
      ["sync_30", 30],
    ]);
  });

  test("corrupt and unsupported custom entries cannot suppress SDK fallback", () => {
    const sdkAssistant: SdkTranscriptContextEntry = {
      type: "message",
      message: {
        role: "assistant",
        timestamp: 100,
        content: [{ type: "toolCall", id: "tc_bad", name: "bash", arguments: { command: "pwd" } }],
      },
    };
    const candidate = {
      kind: "tool_requested",
      eventId: "future-request",
      sessionId,
      ts: 200,
      toolCallId: "tc_bad",
      tool: "bash",
      args: { command: "pwd" },
    } satisfies TranscriptEvent;
    const entries: SdkTranscriptContextEntry[] = [
      sdkAssistant,
      { type: "custom", customType: TRANSCRIPT_EVENT_CUSTOM_TYPE, data: { ...candidate, ts: -1 } },
      durableEntry(candidate, "outpost-pi.transcript-event.v2"),
      { type: "custom", customType: "other-extension.state", data: candidate },
    ];

    expect(reconcileTranscriptContextEntries({ sessionId, entries }))
      .toEqual([expect.objectContaining({ kind: "tool_requested", toolCallId: "tc_bad", ts: 100 })]);
  });

  test("rehomes forked durable events to the current session while preserving identity", () => {
    const copied = { ...user("copied-client", "from parent", 50), sessionId: "parent-session" };
    expect(reconcileTranscriptContextEntries({
      sessionId: "fork-session",
      entries: [durableEntry(copied)],
    })).toEqual([{ ...copied, sessionId: "fork-session" }]);
  });

  test("mixed pre-upgrade history falls back while later durable identity wins", () => {
    const durableLater: TranscriptEvent = {
      kind: "user_confirmed",
      eventId: "app-later",
      sessionId,
      ts: 201,
      clientMessageId: "app-client-later",
      text: "after upgrade",
    };
    const mapped = reconcileTranscriptContextEntries({
      sessionId,
      entries: [
        { type: "message", message: { role: "user", content: "before upgrade", timestamp: 100 } },
        { type: "message", message: { role: "user", content: "after upgrade", timestamp: 200 } },
        durableEntry(durableLater),
      ],
    });

    expect(mapped.filter((event) => event.kind === "user_confirmed").map((event) => event.clientMessageId))
      .toEqual(["sync_100", "app-client-later"]);
  });

  test("reopens durable steering behavior alongside pre-upgrade SDK user fallback", () => {
    const steer: TranscriptEvent = {
      kind: "user_confirmed",
      eventId: "durable-steer",
      sessionId,
      ts: 201,
      clientMessageId: "steer-client",
      text: "refine the active turn",
      streamingBehavior: "steer",
    };
    const reopened = reconcileTranscriptContextEntries({
      sessionId,
      entries: [
        { type: "message", message: { role: "user", content: "before upgrade", timestamp: 100 } },
        durableEntry(steer),
      ],
    });

    expect(reopened).toEqual([
      expect.objectContaining({ kind: "user_confirmed", clientMessageId: "sync_100" }),
      steer,
    ]);
    expect(projectSessionHistory({ sessionId, events: reopened, limit: 10 }).events).toEqual([
      { ts: 100, type: "user_input", id: "sync_100", text: "before upgrade" },
      {
        ts: 201,
        type: "user_input",
        id: "steer-client",
        text: "refine the active turn",
        streaming_behavior: "steer",
      },
    ]);
  });

  test("maps raw compaction timestamps and ignores duplicate durable identities", () => {
    const compacted: TranscriptEvent = {
      kind: "compaction_recorded",
      eventId: "durable-compaction",
      sessionId,
      ts: 500,
      summary: "durable",
    };
    const mapped = reconcileTranscriptContextEntries({
      sessionId,
      entries: [
        { type: "compaction", summary: "raw", tokensBefore: 12, timestamp: "2026-08-25T00:00:00.000Z" },
        { type: "compaction", summary: "invalid date", tokensBefore: 13, timestamp: "not-a-date" },
        durableEntry(compacted),
        durableEntry({ ...compacted, ts: 999 }),
      ],
    });

    expect(mapped.map((event) => [event.kind, event.ts, event.eventId])).toEqual([
      ["compaction_recorded", Date.parse("2026-08-25T00:00:00.000Z"), expect.any(String)],
      ["compaction_recorded", 0, expect.any(String)],
      ["compaction_recorded", 500, "durable-compaction"],
    ]);
  });

  test("reopens one durable compaction over its matching raw SDK fallback", () => {
    const ts = Date.parse("2026-08-25T00:00:00.000Z");
    const durable: TranscriptEvent = {
      kind: "compaction_recorded",
      eventId: deterministicTranscriptEventId(sessionId, "compaction_recorded", String(ts)),
      sessionId,
      ts,
      summary: "same compacted interval",
      tokensBefore: 1200,
    };
    const reopened = reconcileTranscriptContextEntries({
      sessionId,
      entries: [
        {
          type: "compaction",
          summary: "same compacted interval",
          tokensBefore: 1200,
          timestamp: "2026-08-25T00:00:00.000Z",
        },
        durableEntry(durable),
      ],
    });

    expect(reopened).toEqual([durable]);
    expect(projectSessionHistory({ sessionId, events: reopened, limit: 10 }).events).toEqual([
      {
        ts,
        type: "compaction",
        summary: "same compacted interval",
        tokens_before: 1200,
      },
    ]);
  });

  test("tool result stringification is shared by live and replay paths", () => {
    expect(stringifyToolResult({ content: [{ type: "text", text: "ping failed" }], details: {} }))
      .toBe("ping failed");
    expect(stringifyToolResult({ code: 1 })).toBe('{"code":1}');
  });
});

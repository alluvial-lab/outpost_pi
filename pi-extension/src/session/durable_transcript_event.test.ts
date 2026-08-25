import { describe, expect, test } from "vitest";
import type { TranscriptEvent } from "./transcript_event.js";
import {
  TRANSCRIPT_EVENT_CUSTOM_TYPE,
  decodeDurableTranscriptEntry,
  encodeDurableTranscriptEventV1,
} from "./durable_transcript_event.js";

function entry(data: unknown, customType = TRANSCRIPT_EVENT_CUSTOM_TYPE): unknown {
  return {
    type: "custom",
    id: "sdk-entry",
    parentId: null,
    timestamp: "2026-08-25T00:00:00.000Z",
    customType,
    data,
  };
}

const events: TranscriptEvent[] = [
  {
    kind: "user_confirmed",
    eventId: "user-1",
    sessionId: "session-1",
    ts: 1,
    turnId: "turn-1",
    clientMessageId: "client-1",
    text: "show this",
    images: [{ data: "aGVsbG8=", mime: "image/png" }],
    streamingBehavior: "steer",
  },
  {
    kind: "assistant_committed",
    eventId: "assistant-1",
    sessionId: "session-1",
    ts: 2,
    messageId: "message-1",
    replyTo: "client-1",
    text: "done",
    usage: { input_tokens: 4, output_tokens: 2 },
  },
  {
    kind: "tool_requested",
    eventId: "tool-request-1",
    sessionId: "session-1",
    ts: 3,
    toolCallId: "call-1",
    tool: "read",
    args: { path: "/tmp/a", nested: [null, true, 2] },
  },
  {
    kind: "tool_finished",
    eventId: "tool-finish-1",
    sessionId: "session-1",
    ts: 4,
    toolCallId: "call-1",
    result: { ok: true, rows: [1, 2] },
  },
  {
    kind: "provider_error",
    eventId: "error-1",
    sessionId: "session-1",
    ts: 5,
    replyTo: "client-1",
    code: "provider_unavailable",
    message: "try again",
  },
  {
    kind: "compaction_recorded",
    eventId: "compaction-1",
    sessionId: "session-1",
    ts: 6,
    summary: "earlier work",
    tokensBefore: 1200,
  },
];

describe("durable transcript event v1 codec", () => {
  test.each(events.map((event) => [event.kind, event] as const))(
    "round-trips %s exactly",
    (_kind, event) => {
      const encoded = encodeDurableTranscriptEventV1(event);
      expect(decodeDurableTranscriptEntry(entry(encoded))).toEqual({ status: "decoded", event });
    },
  );

  test.each([
    ["missing data", { type: "custom", customType: TRANSCRIPT_EVENT_CUSTOM_TYPE }],
    ["wrong entry type", { type: "message", customType: TRANSCRIPT_EVENT_CUSTOM_TYPE, data: events[0] }],
    ["unknown kind", entry({ ...events[0], kind: "future_event" })],
    ["empty event id", entry({ ...events[0], eventId: "" })],
    ["empty session id", entry({ ...events[0], sessionId: "" })],
    ["negative timestamp", entry({ ...events[0], ts: -1 })],
    ["fractional timestamp", entry({ ...events[0], ts: 1.5 })],
    ["unsafe timestamp", entry({ ...events[0], ts: Number.MAX_SAFE_INTEGER + 1 })],
    ["empty optional turn id", entry({ ...events[0], turnId: "" })],
    ["wrong arm field", entry({ ...events[0], toolCallId: "call-1" })],
    ["unexpected property", entry({ ...events[0], surprise: true })],
    ["explicit undefined optional field", entry({ ...events[0], images: undefined })],
    ["invalid image", entry({ ...events[0], images: [{ data: "x", mime: "image/png", extra: true }] })],
    ["invalid usage", entry({ ...events[1], usage: { input_tokens: -1, output_tokens: 2 } })],
    ["non-json nested number", entry({ ...events[2], args: { value: Number.POSITIVE_INFINITY } })],
    ["non-json nested bigint", entry({ ...events[2], args: { value: 1n } })],
    ["non-json nested function", entry({ ...events[3], result: { value: () => undefined } })],
    ["non-json nested symbol", entry({ ...events[3], result: Symbol("value") })],
  ])("classifies %s as invalid", (_label, candidate) => {
    expect(decodeDurableTranscriptEntry(candidate)).toEqual({ status: "invalid" });
  });

  test("round-trips an own __proto__ tool-args key without changing object semantics", () => {
    const args = JSON.parse('{"__proto__":{"polluted":true},"path":"/tmp/a"}') as Record<string, unknown>;
    const event = { ...events[2], eventId: "tool-proto", args } as TranscriptEvent;

    const decoded = decodeDurableTranscriptEntry(entry(encodeDurableTranscriptEventV1(event)));

    expect(decoded).toEqual({ status: "decoded", event });
    expect(decoded.status).toBe("decoded");
    if (decoded.status !== "decoded" || decoded.event.kind !== "tool_requested") return;
    expect(Object.hasOwn(decoded.event.args, "__proto__")).toBe(true);
    expect(decoded.event.args["__proto__"]).toEqual({ polluted: true });
    expect((Object.prototype as Record<string, unknown>)["polluted"]).toBeUndefined();
  });

  test("classifies unrelated and unsupported custom entries without parsing them as v1", () => {
    expect(decodeDurableTranscriptEntry(entry(events[0], "another-extension.state")))
      .toEqual({ status: "not_transcript" });
    expect(decodeDurableTranscriptEntry(entry(events[0], "outpost-pi.transcript-event.v2")))
      .toEqual({ status: "unsupported_version" });
  });

  test.each([
    ["cyclic args", () => {
      const args: Record<string, unknown> = {};
      args["self"] = args;
      return { ...events[2], args } as TranscriptEvent;
    }],
    ["unexpected event property", () => ({ ...events[0], extra: true }) as TranscriptEvent],
    ["non-finite result", () => ({ ...events[3], result: Number.NaN }) as TranscriptEvent],
  ])("encoding rejects %s", (_label, makeEvent) => {
    expect(() => encodeDurableTranscriptEventV1(makeEvent())).toThrow();
  });
});

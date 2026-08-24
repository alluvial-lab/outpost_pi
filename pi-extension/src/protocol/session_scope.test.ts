import { describe, expect, test } from "vitest";
import {
  NON_SESSION_SCOPED_SERVER_TYPES,
  SESSION_SCOPED_CLIENT_TYPES,
  SESSION_SCOPED_SERVER_TYPES,
  SERVER_MESSAGE_TYPES,
  isServerMessageType,
  isSessionScopedClientType,
  isSessionScopedServerType,
} from "./session_scope.js";

const expectedSessionScopedServerTypes = new Set([
  "user_input",
  "user_message",
  "queued_message_state",
  "agent_chunk",
  "agent_done",
  "agent_message",
  "compaction",
  "tool_request",
  "tool_result",
  "error",
  "cancelled",
  "session_history",
  "action_ok",
  "action_error",
  "models_list",
  "capture_upload_ack",
  "capture_upload_error",
]);

const expectedSessionScopedClientTypes = new Set([
  "user_message",
  "queued_message_set",
  "queued_message_clear",
  "approve_tool",
  "cancel",
  "session_sync",
  "session_new",
  "session_compact",
  "model_set",
  "thinking_set",
  "list_models",
  "capture_upload_begin",
  "capture_upload_chunk",
  "capture_upload_end",
]);

describe("session-scoped protocol registry", () => {
  test("generates every server push that must carry session_id", () => {
    expect(new Set(SESSION_SCOPED_SERVER_TYPES)).toEqual(expectedSessionScopedServerTypes);
  });

  test("generates every client command scoped to an active session", () => {
    expect(new Set(SESSION_SCOPED_CLIENT_TYPES)).toEqual(expectedSessionScopedClientTypes);
  });

  test("partitions the generated server registry exhaustively", () => {
    const scoped = new Set<string>(SESSION_SCOPED_SERVER_TYPES);
    const nonScoped = new Set<string>(NON_SESSION_SCOPED_SERVER_TYPES);

    expect([...scoped].filter((type) => nonScoped.has(type))).toEqual([]);
    expect(new Set([...scoped, ...nonScoped])).toEqual(new Set(SERVER_MESSAGE_TYPES));
  });

  test("guards codec/server registry drift", () => {
    expect(isServerMessageType("models_list")).toBe(true);
    expect(isServerMessageType("action_ok")).toBe(true);
    expect(isServerMessageType("compaction")).toBe(true);
    expect(SERVER_MESSAGE_TYPES).toContain("user_message");
    expect(isServerMessageType("future_type")).toBe(false);
  });

  test("type predicates distinguish session-scoped families", () => {
    expect(isSessionScopedServerType("session_history")).toBe(true);
    expect(isSessionScopedServerType("pair_ok")).toBe(false);
    expect(isSessionScopedServerType("action_ok")).toBe(true);
    expect(isSessionScopedClientType("session_sync")).toBe(true);
    expect(isSessionScopedClientType("pair_request")).toBe(false);
    expect(isSessionScopedClientType("ping")).toBe(false);
  });
});

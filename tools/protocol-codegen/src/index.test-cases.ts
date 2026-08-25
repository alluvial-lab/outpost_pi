import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath, pathToFileURL } from "node:url";
import assert from "node:assert/strict";

import {
  buildOutpostPiIr,
  emitTypeScriptProtocol,
  loadOutpostPiManifest,
  renderTypeScriptProtocol,
} from "./index.ts";

async function writeJson(path: string, value: unknown): Promise<void> {
  await writeFile(path, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

interface GeneratedProtocolModule {
  readonly RELAY_AUTH_DOMAIN_PREFIX?: string;
  readonly RELAY_DEFAULT_MAX_DECODED_BYTES?: number;
  readonly RELAY_MAX_FRAME_OVERHEAD_BYTES?: number;
  readonly RELAY_MAX_PRE_AUTH_FRAME_BYTES?: number;
  readonly RELAY_MAX_RAW_MESSAGE_BYTES?: number;
  readonly RELAY_SERVER_CONTROL_FRAME_TYPES?: readonly string[];
  readonly relayControlTypes?: readonly string[];
  readonly RELAY_CONTROL_DISCRIMINATORS?: Readonly<Record<string, string>>;
  readonly CLIENT_MESSAGE_TYPES?: readonly string[];
  readonly SERVER_MESSAGE_TYPES?: readonly string[];
  readonly SERVER_MESSAGE_DISCRIMINATORS?: Readonly<Record<string, string>>;
  readonly SESSION_SCOPED_CLIENT_MESSAGE_TYPES?: readonly string[];
  readonly SESSION_SCOPED_SERVER_MESSAGE_TYPES?: readonly string[];
  readonly SESSION_HISTORY_EVENT_TYPES?: readonly string[];
  isClientMessage?(value: unknown): boolean;
  isServerMessage?(value: unknown): boolean;
  isSessionHistoryEvent?(value: unknown): boolean;
  isRelayServerControlFrame?(value: unknown): boolean;
  isRelayOuterEnvelope?(value: unknown): boolean;
  isRelayOuterEnvelopeCompat?(value: unknown): boolean;
  isCrossPcFrame?(value: unknown): boolean;
}

async function importGeneratedProtocol(output: string): Promise<GeneratedProtocolModule> {
  const root = await mkdtemp(join(tmpdir(), "outpost-pi-generated-protocol-import-"));
  const file = join(root, "protocol.generated.ts");
  await writeFile(file, output, "utf8");
  return import(`${pathToFileURL(file).href}?cache=${Date.now()}`) as Promise<GeneratedProtocolModule>;
}

async function writeFixtureProtocol(schema: unknown): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "outpost-pi-protocol-codegen-"));
  const schemaRoot = join(root, "schema");
  await writeFile(join(root, ".keep"), "", "utf8");
  await mkdir(schemaRoot, { recursive: true });
  await writeJson(join(schemaRoot, "manifest.json"), {
    schemaVersion: 1,
    source: "json-schema-2020-12",
    discriminator: "type",
    profiles: ["compat"],
    families: [
      {
        id: "appPiClient",
        transport: "relay-jsonl",
        schema: "schema/minimal.schema.json",
        description: "Minimal test family",
      },
    ],
  });
  await writeJson(join(schemaRoot, "minimal.schema.json"), schema);
  return root;
}

type RegisterTest = (
  name: string,
  run: () => void | Promise<void>,
) => unknown;

export function registerProtocolCodegenTests(test: RegisterTest): void {
test("minimal manifest schema emits deterministic TypeScript output", async () => {
  const protocolRoot = await writeFixtureProtocol({
    $schema: "https://json-schema.org/draft/2020-12/schema",
    oneOf: [{ $ref: "#/$defs/pong" }, { $ref: "#/$defs/error" }],
    $defs: {
      pong: {
        type: "object",
        required: ["type", "in_reply_to"],
        properties: {
          type: { const: "pong" },
          in_reply_to: { type: "string" },
          session_id: { type: "string" },
        },
        additionalProperties: false,
        "x-outpost-pi": { profileRequired: { "canonical-session": ["session_id"] } },
      },
      error: {
        type: "object",
        required: ["type", "message"],
        properties: {
          type: { const: "error" },
          message: { type: "string" },
          code: { enum: ["invalid_message", "internal_error"] },
        },
        additionalProperties: false,
      },
    },
  });

  const manifest = await loadOutpostPiManifest(join(protocolRoot, "schema", "manifest.json"));
  const ir = await buildOutpostPiIr(manifest, { profile: "compat" });
  const first = renderTypeScriptProtocol(ir);
  const second = renderTypeScriptProtocol(ir);

  assert.equal(second, first);
  assert.match(first, /export const CLIENT_MESSAGE_TYPES = \[/);
  assert.doesNotMatch(first, /CLIENT_MESSAGE_DISCRIMINATORS/);
  assert.match(first, /export const appPiClientTypes = CLIENT_MESSAGE_TYPES;/);
  assert.match(first, /export function isClientMessage\(value: unknown\): value is ClientMessage/);
  assert.doesNotMatch(first, /function isFiniteNumber/);

  const generated = await importGeneratedProtocol(first);
  assert.deepEqual(generated.CLIENT_MESSAGE_TYPES, ["pong", "error"]);
  assert.deepEqual(generated.SESSION_SCOPED_CLIENT_MESSAGE_TYPES, ["pong"]);
  assert.equal(generated.isClientMessage?.({ type: "pong", in_reply_to: "reply-1" }), true);
  assert.equal(generated.isClientMessage?.({ type: "error", message: "bad", code: "invalid_message" }), true);
  assert.equal(generated.isClientMessage?.({ in_reply_to: "reply-1" }), false);
  assert.equal(generated.isClientMessage?.({ type: "pong" }), false);
  assert.equal(generated.isClientMessage?.({ type: "error", message: "bad", code: "future_code" }), false);
});

test("number schemas emit only the finite-number helpers their validators reference", async () => {
  const protocolRoot = await writeFixtureProtocol({
    $schema: "https://json-schema.org/draft/2020-12/schema",
    oneOf: [{ $ref: "#/$defs/measurement" }],
    $defs: {
      measurement: {
        type: "object",
        required: ["type", "ratio"],
        properties: {
          type: { const: "measurement" },
          ratio: { type: "number", minimum: 0 },
        },
        additionalProperties: false,
      },
    },
  });

  const manifest = await loadOutpostPiManifest(join(protocolRoot, "schema", "manifest.json"));
  const output = renderTypeScriptProtocol(await buildOutpostPiIr(manifest, { profile: "compat" }));

  assert.match(output, /function isFiniteNumber\(value: unknown\): value is number/);
  assert.match(output, /function isFiniteNumberAtLeast\(value: unknown, minimum: number\): value is number/);
});

test("number-only schemas emit the base finite-number helper and reject non-finite values", async () => {
  const protocolRoot = await writeFixtureProtocol({
    $schema: "https://json-schema.org/draft/2020-12/schema",
    oneOf: [{ $ref: "#/$defs/measurement" }],
    $defs: {
      measurement: {
        type: "object",
        required: ["type", "ratio"],
        properties: {
          type: { const: "measurement" },
          ratio: { type: "number" },
        },
        additionalProperties: false,
      },
    },
  });

  const manifest = await loadOutpostPiManifest(join(protocolRoot, "schema", "manifest.json"));
  const output = renderTypeScriptProtocol(await buildOutpostPiIr(manifest, { profile: "compat" }));

  assert.match(output, /function isFiniteNumber\(value: unknown\): value is number/);
  assert.doesNotMatch(output, /function isFiniteNumberAtLeast\(/);

  const generated = await importGeneratedProtocol(output);
  assert.equal(generated.isClientMessage?.({ type: "measurement", ratio: 1.5 }), true);
  assert.equal(generated.isClientMessage?.({ type: "measurement", ratio: 0 }), true);
  assert.equal(generated.isClientMessage?.({ type: "measurement", ratio: Number.NaN }), false);
  assert.equal(generated.isClientMessage?.({ type: "measurement", ratio: Number.POSITIVE_INFINITY }), false);
  assert.equal(generated.isClientMessage?.({ type: "measurement", ratio: Number.NEGATIVE_INFINITY }), false);
});

test("Outpost-Pi schema emits generated app/Pi unions and shared value types", async () => {
  const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
  const manifest = await loadOutpostPiManifest(join(repoRoot, "protocol", "schema", "manifest.json"));
  const ir = await buildOutpostPiIr(manifest, { profile: "compat" });
  const output = renderTypeScriptProtocol(ir);

  assert.match(output, /export const RELAY_AUTH_DOMAIN_PREFIX = "outpost-pi-relay-auth-v1\\n";/);
  assert.match(output, /export const RELAY_DEFAULT_MAX_DECODED_BYTES = 4194304;/);
  assert.match(output, /export const RELAY_MAX_FRAME_OVERHEAD_BYTES = 65536;/);
  assert.match(output, /export const RELAY_MAX_PRE_AUTH_FRAME_BYTES = 16384;/);
  assert.match(output, /export interface RelayOuterEnvelope \{\n  readonly peer: string;\n  readonly room: string;\n  readonly ct: string;\n\}/);
  assert.match(output, /export interface RelayOuterEnvelopeCompat \{\n  readonly peer: string;\n  readonly room\?: string;\n  readonly ct: string;\n\}/);
  assert.match(output, /export type RelayServerControlFrame = Extract<RelayControlFrame/);
  assert.match(output, /export const RELAY_CONTROL_DISCRIMINATORS = \{[\s\S]*hello: "hello",[\s\S]*auth: "auth",[\s\S]*subscribe_presence: "subscribe_presence",[\s\S]*room_meta_update: "room_meta_update",/);
  assert.match(output, /export function isRelayOuterEnvelope\(value: unknown\): value is RelayOuterEnvelope/);
  assert.match(output, /export function isRelayOuterEnvelopeCompat\(value: unknown\): value is RelayOuterEnvelopeCompat/);
  assert.match(output, /export function isCrossPcFrame\(value: unknown\): value is CrossPcFrame/);
  assert.match(output, /export function isRelayServerControlFrame/);
  assert.match(output, /export interface WireImage \{\n  readonly data: string;\n  readonly mime: string;\n\}/);
  assert.match(output, /export interface Usage \{\n  readonly input_tokens: number;\n  readonly output_tokens: number;\n\}/);
  assert.match(output, /export interface WireModel \{[\s\S]*readonly vision\?: boolean;[\s\S]*\}/);
  assert.match(output, /export type ThinkingLevel = "off" \| "minimal" \| "low" \| "medium" \| "high" \| "xhigh";/);
  assert.match(output, /export type StreamingBehavior = "steer";/);
  assert.match(output, /export type ByeReason = "peer_stop" \| "session_replaced" \| "shutdown";/);
  assert.match(output, /export type PairErrorCode = "token_expired" \| "token_consumed" \| "token_unknown" \| "bad_dh_sig" \| "internal_error";/);
  assert.match(output, /export type KnownErrorCode = "tool_approval_required"[\s\S]*"session_mismatch" \| "delivery_pending";/);
  assert.match(output, /export type ErrorCode = KnownErrorCode \| \(string & \{\}\);/);
  assert.match(output, /export type SessionHistoryEvent =\n  \| HistoryUserInput\n  \| HistoryToolRequest\n  \| HistoryToolResult\n  \| HistoryAgentMessage\n  \| HistoryCompaction\n  \| HistoryError;/);

  assert.match(output, /export interface PairOk \{[\s\S]*readonly session_id\?: string;[\s\S]*readonly room_id: string;[\s\S]*\}/);
  assert.match(output, /readonly images\?: Array<WireImage>;/);
  assert.match(output, /readonly usage\?: Usage;/);
  assert.match(output, /readonly events: Array<SessionHistoryEvent>;/);
  assert.match(output, /readonly level: ThinkingLevel;/);
  assert.match(output, /readonly reason: ByeReason;/);
  assert.match(output, /readonly code: PairErrorCode;/);
  assert.match(output, /readonly code: ErrorCode;/);
  assert.match(output, /readonly models: Array<WireModel>;/);

  assert.match(output, /export type ClientMessage =\n  \| PairRequest\n  \| UserMessage\n  \| QueuedMessageSet\n  \| QueuedMessageClear\n  \| ApproveTool\n  \| Cancel\n  \| Ping\n  \| SessionSync\n  \| SessionNew\n  \| SessionCompact\n  \| ModelSet\n  \| ThinkingSet\n  \| ListModels\n  \| CaptureUploadBegin\n  \| CaptureUploadChunk\n  \| CaptureUploadEnd;/);
  assert.match(output, /export type ServerMessage =\n  \| PairOk\n  \| PairError\n  \| UserInput\n  \| UserMessage\n  \| QueuedMessageState\n  \| AgentChunk\n  \| AgentDone\n  \| AgentMessage\n  \| Compaction\n  \| ToolRequest\n  \| ToolResult\n  \| ErrorMessage\n  \| Cancelled\n  \| Pong\n  \| Bye\n  \| SessionHistory\n  \| ActionOk\n  \| ActionError\n  \| ModelsList\n  \| CaptureUploadAck\n  \| CaptureUploadError;/);
  assert.doesNotMatch(output, /CLIENT_MESSAGE_DISCRIMINATORS/);
  assert.match(output, /export const SERVER_MESSAGE_TYPES = \[/);
  assert.match(output, /export const SERVER_MESSAGE_DISCRIMINATORS = \{[\s\S]*pair_ok: "pair_ok",[\s\S]*pair_error: "pair_error",[\s\S]*bye: "bye",/);
  assert.match(output, /export const SESSION_SCOPED_CLIENT_MESSAGE_TYPES = \[/);
  assert.match(output, /export const SESSION_SCOPED_SERVER_MESSAGE_TYPES = \[/);
  assert.match(output, /"user_message",\n  "queued_message_state",/);
  assert.match(output, /"compaction",\n  "tool_request",/);
  assert.match(output, /"action_ok",\n  "action_error",\n  "models_list",/);
  assert.match(output, /export const SESSION_HISTORY_EVENT_TYPES = \[/);
  assert.match(output, /export function isServerMessage\(value: unknown\): value is ServerMessage/);
  assert.doesNotMatch(output, /isStringWithMinLength|isFiniteNumberAtLeast/);
  assert.doesNotMatch(output, /ServerMessagePairOk|ClientMessageUserMessage/);
});

test("Outpost-Pi generated validators accept current app/Pi variants and reject malformed objects", async () => {
  const repoRoot = fileURLToPath(new URL("../../..", import.meta.url));
  const manifest = await loadOutpostPiManifest(join(repoRoot, "protocol", "schema", "manifest.json"));
  const ir = await buildOutpostPiIr(manifest, { profile: "compat" });
  const generated = await importGeneratedProtocol(renderTypeScriptProtocol(ir));

  assert.equal(generated.RELAY_AUTH_DOMAIN_PREFIX, "outpost-pi-relay-auth-v1\n");
  assert.equal(generated.RELAY_DEFAULT_MAX_DECODED_BYTES, 4 * 1024 * 1024);
  assert.equal(generated.RELAY_MAX_FRAME_OVERHEAD_BYTES, 64 * 1024);
  assert.equal(generated.RELAY_MAX_PRE_AUTH_FRAME_BYTES, 16 * 1024);
  assert.equal(generated.RELAY_MAX_RAW_MESSAGE_BYTES, 5_657_944);
  assert.deepEqual(generated.RELAY_SERVER_CONTROL_FRAME_TYPES, [
    "challenge",
    "presence",
    "peer_online",
    "peer_offline",
    "rooms",
    "room_announced",
    "room_ended",
    "room_meta_updated",
  ]);
  assert.deepEqual(
    generated.RELAY_CONTROL_DISCRIMINATORS,
    Object.fromEntries((generated.relayControlTypes ?? []).map((type) => [type, type])),
  );
  assert.equal(generated.RELAY_CONTROL_DISCRIMINATORS?.hello, "hello");
  assert.equal(generated.RELAY_CONTROL_DISCRIMINATORS?.auth, "auth");
  assert.equal(generated.RELAY_CONTROL_DISCRIMINATORS?.room_meta_update, "room_meta_update");
  assert.equal(generated.RELAY_CONTROL_DISCRIMINATORS?.subscribe_presence, "subscribe_presence");
  assert.equal(generated.isRelayServerControlFrame?.({ type: "peer_online", peer: "pi-a" }), true);
  assert.equal(generated.isRelayServerControlFrame?.({ type: "subscribe_presence", peers: [] }), false);

  const strictOuter = { peer: "owner-a", room: "main", ct: "e30=" };
  assert.equal(generated.isRelayOuterEnvelope?.(strictOuter), true);
  assert.equal(generated.isRelayOuterEnvelope?.({ peer: "owner-a", ct: "e30=" }), false);
  assert.equal(generated.isRelayOuterEnvelopeCompat?.({ peer: "owner-a", ct: "e30=" }), true);
  assert.equal(generated.isRelayOuterEnvelopeCompat?.({ ...strictOuter, future: true }), false);
  assert.equal(generated.isRelayOuterEnvelopeCompat?.({ ...strictOuter, room: "" }), false);

  const crossPc = {
    type: "pi_envelope_in",
    from_pc: "pi-a",
    to_room: "main",
    envelope: { from: "a:session", to: ["b:agent"], id: "id-1", re: "id-0", body: {} },
  };
  assert.equal(generated.isCrossPcFrame?.(crossPc), true);
  assert.equal(generated.isCrossPcFrame?.({
    ...crossPc,
    envelope: { ...crossPc.envelope, to: [] },
  }), false);
  assert.equal(generated.isCrossPcFrame?.({
    ...crossPc,
    envelope: { ...crossPc.envelope, re: "" },
  }), false);
  assert.equal(generated.isCrossPcFrame?.({
    ...crossPc,
    envelope: { ...crossPc.envelope, extra: true },
  }), false);
  assert.deepEqual(generated.SERVER_MESSAGE_TYPES, [
    "pair_ok",
    "pair_error",
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
    "pong",
    "bye",
    "session_history",
    "action_ok",
    "action_error",
    "models_list",
    "capture_upload_ack",
    "capture_upload_error",
  ]);
  assert.equal(generated.SERVER_MESSAGE_DISCRIMINATORS?.pair_ok, "pair_ok");
  assert.equal(generated.SERVER_MESSAGE_DISCRIMINATORS?.pair_error, "pair_error");
  assert.equal(generated.SERVER_MESSAGE_DISCRIMINATORS?.bye, "bye");
  assert.deepEqual(generated.SESSION_SCOPED_CLIENT_MESSAGE_TYPES, [
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
  assert.deepEqual(generated.SESSION_SCOPED_SERVER_MESSAGE_TYPES, [
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
  assert.deepEqual(generated.SESSION_HISTORY_EVENT_TYPES, ["user_input", "tool_request", "tool_result", "agent_message", "compaction", "error"]);

  const image = { data: "base64", mime: "image/jpeg" };
  const usage = { input_tokens: 1, output_tokens: 2 };
  const model = { id: "model-1", name: "Model One", provider: "provider", reasoning: true, context_window: 200000, vision: true };
  const clientFixtures: unknown[] = [
    { type: "pair_request", id: "c1", token_id: "dG9rZW4taWQtMTY", pair_mac: "cGFpci1tYWMtMzItYnl0ZXM", device_name: "phone" },
    { type: "user_message", id: "c2", text: "hello", images: [image], streaming_behavior: "steer" },
    { type: "queued_message_set", id: "c3", text: "next" },
    { type: "queued_message_clear", id: "c4" },
    { type: "approve_tool", id: "c5", tool_call_id: "tool-1", decision: "allow" },
    { type: "cancel", id: "c6", target_id: "turn-1" },
    { type: "ping", id: "c7" },
    { type: "session_sync", id: "c8", limit: 25 },
    { type: "session_new", id: "c9" },
    { type: "session_compact", id: "c10" },
    { type: "model_set", id: "c11", provider: "openai", model_id: "gpt" },
    { type: "thinking_set", id: "c12", level: "high" },
    { type: "list_models", id: "c13" },
    { type: "capture_upload_begin", id: "c14", upload_id: "upload-1", device_label: "phone", total_bytes: 2, capture_kind: "debug_log_jsonl" },
    { type: "capture_upload_chunk", id: "c15", upload_id: "upload-1", sequence: 0, payload: "e30K" },
    { type: "capture_upload_end", id: "c16", upload_id: "upload-1", sha256: "0".repeat(64) },
  ];
  for (const fixture of clientFixtures) assert.equal(generated.isClientMessage?.(fixture), true, JSON.stringify(fixture));

  const historyEvents = [
    { ts: 1, type: "user_input", id: "h1", text: "hi", images: [image] },
    { ts: 2, type: "tool_request", tool_call_id: "tool-1", tool: "read", args: { path: "README.md" } },
    { ts: 3, type: "tool_result", tool_call_id: "tool-1", result: ["ok"] },
    { ts: 4, type: "agent_message", in_reply_to: "h1", text: "done", usage },
    { ts: 5, type: "compaction", summary: "short", tokens_before: 100 },
    { ts: 6, type: "error", in_reply_to: "h1", code: "provider_error", message: "provider failed" },
  ];
  for (const event of historyEvents) assert.equal(generated.isSessionHistoryEvent?.(event), true, JSON.stringify(event));

  const serverFixtures: unknown[] = [
    { type: "pair_ok", in_reply_to: "c1", session_name: "main", session_started_at: 0, room_id: "room-1", harness: { name: "pi", version: "1" }, hostname: "host" },
    { type: "pair_error", in_reply_to: "c1", code: "token_expired", message: "expired" },
    { type: "user_input", id: "s1", text: "input", images: [image], streaming_behavior: "steer" },
    { type: "user_message", id: "s2", text: "echo" },
    { type: "queued_message_state" },
    { type: "agent_chunk", in_reply_to: "s1", delta: "d" },
    { type: "agent_done", in_reply_to: "s1", usage },
    { type: "agent_message", in_reply_to: "s1", text: "answer", usage },
    { type: "compaction", summary: "short", tokens_before: 100, ts: 10 },
    { type: "tool_request", tool_call_id: "tool-1", tool: "read", args: { path: "README.md" } },
    { type: "tool_result", tool_call_id: "tool-1", result: { ok: true } },
    { type: "error", code: "future_code", message: "future codes stay open" },
    { type: "cancelled", in_reply_to: "s1", target_id: "turn-1" },
    { type: "pong", in_reply_to: "ping-1" },
    { type: "bye", reason: "shutdown" },
    { type: "session_history", in_reply_to: "sync-1", session_started_at: 0, events: historyEvents, eos: true, truncated: false },
    { type: "action_ok", in_reply_to: "action-1", action: "session_new" },
    { type: "action_error", in_reply_to: "action-2", action: "model_set", error: "no model" },
    { type: "models_list", in_reply_to: "models-1", models: [model], current: model },
    { type: "capture_upload_ack", in_reply_to: "c14", upload_id: "upload-1", stage: "delivered", path: "debug/capture.bin", bytes: 2, events: 1 },
    { type: "capture_upload_error", in_reply_to: "c14", upload_id: "upload-1", code: "too_large", message: "too large" },
  ];
  for (const fixture of serverFixtures) assert.equal(generated.isServerMessage?.(fixture), true, JSON.stringify(fixture));

  assert.equal(generated.isClientMessage?.({ id: "missing-type" }), false);
  assert.equal(generated.isClientMessage?.({ type: "model_set", id: "bad", provider: 1, model_id: "gpt" }), false);
  assert.equal(generated.isServerMessage?.({ type: "models_list", in_reply_to: "bad", models: [{ id: "missing-required-model-fields" }] }), false);
  assert.equal(generated.isServerMessage?.({ type: "tool_request", tool_call_id: "tool-1", tool: "read" }), false);
  assert.equal(generated.isSessionHistoryEvent?.({ type: "compaction", ts: 1, summary: "bad", tokens_before: "many" }), false);
  assert.equal(generated.isServerMessage?.({ type: "future_type" }), false);
});

test("placeholder schema families fail with a clear diagnostic", async () => {
  const protocolRoot = await writeFixtureProtocol({
    $schema: "https://json-schema.org/draft/2020-12/schema",
    oneOf: [],
    $defs: {},
    "x-outpost-pi": { family: "appPiClient" },
  });
  const manifest = await loadOutpostPiManifest(join(protocolRoot, "schema", "manifest.json"));
  await assert.rejects(
    () => buildOutpostPiIr(manifest, { profile: "compat" }),
    /schema family placeholder: appPiClient \(schema\/minimal\.schema\.json\)/,
  );
});

test("emitTypeScriptProtocol check detects stale generated output", async () => {
  const protocolRoot = await writeFixtureProtocol({
    $schema: "https://json-schema.org/draft/2020-12/schema",
    oneOf: [{ $ref: "#/$defs/ping" }],
    $defs: {
      ping: {
        type: "object",
        required: ["type", "id"],
        properties: { type: { const: "ping" }, id: { type: "string" } },
        additionalProperties: false,
      },
    },
  });
  const manifest = await loadOutpostPiManifest(join(protocolRoot, "schema", "manifest.json"));
  const ir = await buildOutpostPiIr(manifest, { profile: "compat" });
  const outFile = join(protocolRoot, "generated", "protocol.generated.ts");

  await emitTypeScriptProtocol(ir, { outFile });
  await emitTypeScriptProtocol(ir, { outFile, check: true });
  await writeFile(outFile, "stale\n", "utf8");
  await assert.rejects(
    () => emitTypeScriptProtocol(ir, { outFile, check: true }),
    /Generated TypeScript protocol is stale/,
  );
});
}

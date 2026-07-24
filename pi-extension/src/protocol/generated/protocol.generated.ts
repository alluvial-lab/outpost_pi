// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
/* eslint-disable */

export type JsonValue = null | boolean | number | string | JsonValue[] | { readonly [key: string]: JsonValue };

export type StreamingBehavior = "steer";

export interface WireImage {
  readonly data: string;
  readonly mime: string;
}

export interface Usage {
  readonly input_tokens: number;
  readonly output_tokens: number;
}

export type PairErrorCode = "token_expired" | "token_consumed" | "token_unknown" | "bad_dh_sig" | "internal_error";

export type KnownErrorCode = "tool_approval_required" | "invalid_message" | "unsupported_type" | "too_large" | "rate_limited" | "timeout" | "internal_error" | "session_mismatch" | "delivery_pending";

export type ErrorCode = KnownErrorCode | (string & {});

export type ActionName = "session_new" | "session_compact" | "model_set" | "thinking_set";

export type ThinkingLevel = "off" | "minimal" | "low" | "medium" | "high" | "xhigh";

export interface WireModel {
  readonly id: string;
  readonly name: string;
  readonly provider: string;
  readonly reasoning: boolean;
  readonly context_window: number;
  readonly vision?: boolean;
}

export type ByeReason = "peer_stop" | "session_replaced" | "shutdown";

export interface HistoryUserInput {
  readonly ts: number;
  readonly type: "user_input";
  readonly id: string;
  readonly text: string;
  readonly images?: Array<WireImage>;
}

export interface HistoryToolRequest {
  readonly ts: number;
  readonly type: "tool_request";
  readonly tool_call_id: string;
  readonly tool: string;
  readonly args: unknown;
}

export interface HistoryToolResult {
  readonly ts: number;
  readonly type: "tool_result";
  readonly tool_call_id: string;
  readonly result?: unknown;
  readonly error?: string;
}

export interface HistoryAgentMessage {
  readonly ts: number;
  readonly type: "agent_message";
  readonly in_reply_to: string;
  readonly text: string;
  readonly message_id?: string;
  readonly usage?: Usage;
}

export interface HistoryCompaction {
  readonly ts: number;
  readonly type: "compaction";
  readonly summary: string;
  readonly tokens_before: number;
}

export type SessionHistoryEvent =
  | HistoryUserInput
  | HistoryToolRequest
  | HistoryToolResult
  | HistoryAgentMessage
  | HistoryCompaction;

export const RELAY_AUTH_DOMAIN_PREFIX = "outpost-pi-relay-auth-v1\n";

export const RELAY_DEFAULT_MAX_DECODED_BYTES = 4194304;
export const RELAY_MAX_FRAME_OVERHEAD_BYTES = 65536;
export const RELAY_MAX_PRE_AUTH_FRAME_BYTES = 16384;
export const RELAY_MAX_RAW_MESSAGE_BYTES =
  4 * Math.ceil(RELAY_DEFAULT_MAX_DECODED_BYTES / 3) + RELAY_MAX_FRAME_OVERHEAD_BYTES;
export const RELAY_MAX_DEVICE_ID_BYTES = 128;
export const RELAY_MAX_ROOM_ID_BYTES = 256;
export const RELAY_MAX_ROOM_NAME_BYTES = 256;
export const RELAY_MAX_CWD_BYTES = 4096;
export const RELAY_MAX_SESSION_ID_BYTES = 512;
export const RELAY_MAX_MODEL_BYTES = 256;
export const RELAY_MAX_THINKING_BYTES = 32;

export interface RelayOuterEnvelope {
  readonly peer: string;
  readonly room: string;
  readonly ct: string;
}

export interface RelayOuterEnvelopeCompat {
  readonly peer: string;
  readonly room?: string;
  readonly ct: string;
}

export const protocolManifest = {
  schemaVersion: 1,
  source: "json-schema-2020-12",
  profile: "compat",
  authDomainPrefix: RELAY_AUTH_DOMAIN_PREFIX,
  families: [
    { id: "appPiClient", union: "ClientMessage", transport: "relay-jsonl" },
    { id: "appPiServer", union: "ServerMessage", transport: "relay-jsonl" },
    { id: "relayControl", union: "RelayControlFrame", transport: "relay-jsonl" },
    { id: "crossPc", union: "CrossPcFrame", transport: "relay-jsonl" },
    { id: "cockpitControl", union: "CockpitControlFrame", transport: "pi-custom-event" },
  ],
} as const;

export const CLIENT_MESSAGE_TYPES = [
  "pair_request",
  "user_message",
  "queued_message_set",
  "queued_message_clear",
  "approve_tool",
  "cancel",
  "ping",
  "session_sync",
  "session_new",
  "session_compact",
  "model_set",
  "thinking_set",
  "list_models",
] as const;
export const CLIENT_MESSAGE_DISCRIMINATORS = {
  pair_request: "pair_request",
  user_message: "user_message",
  queued_message_set: "queued_message_set",
  queued_message_clear: "queued_message_clear",
  approve_tool: "approve_tool",
  cancel: "cancel",
  ping: "ping",
  session_sync: "session_sync",
  session_new: "session_new",
  session_compact: "session_compact",
  model_set: "model_set",
  thinking_set: "thinking_set",
  list_models: "list_models",
} as const;
export type ClientMessageType = (typeof CLIENT_MESSAGE_TYPES)[number];
export const SESSION_SCOPED_CLIENT_MESSAGE_TYPES = [
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
] as const;
export const appPiClientTypes = CLIENT_MESSAGE_TYPES;
export type AppPiClientType = ClientMessageType;

export interface PairRequest {
  readonly type: "pair_request";
  readonly id: string;
  readonly token_id?: string;
  readonly pair_mac?: string;
  readonly device_name: string;
  readonly dh_pk?: string;
  readonly dh_sig?: string;
}

export interface UserMessage {
  readonly type: "user_message";
  readonly id: string;
  readonly session_id?: string;
  readonly text: string;
  readonly images?: Array<WireImage>;
  readonly streaming_behavior?: StreamingBehavior;
  readonly ts?: number;
}

export interface QueuedMessageSet {
  readonly type: "queued_message_set";
  readonly id: string;
  readonly session_id?: string;
  readonly text: string;
}

export interface QueuedMessageClear {
  readonly type: "queued_message_clear";
  readonly id: string;
  readonly session_id?: string;
}

export interface ApproveTool {
  readonly type: "approve_tool";
  readonly id: string;
  readonly session_id?: string;
  readonly tool_call_id: string;
  readonly decision: "allow" | "deny";
}

export interface Cancel {
  readonly type: "cancel";
  readonly id: string;
  readonly session_id?: string;
  readonly target_id: string;
}

export interface Ping {
  readonly type: "ping";
  readonly id: string;
}

export interface SessionSync {
  readonly type: "session_sync";
  readonly id: string;
  readonly session_id?: string;
  readonly limit?: number;
}

export interface SessionNew {
  readonly type: "session_new";
  readonly id: string;
  readonly session_id?: string;
}

export interface SessionCompact {
  readonly type: "session_compact";
  readonly id: string;
  readonly session_id?: string;
}

export interface ModelSet {
  readonly type: "model_set";
  readonly id: string;
  readonly session_id?: string;
  readonly provider: string;
  readonly model_id: string;
}

export interface ThinkingSet {
  readonly type: "thinking_set";
  readonly id: string;
  readonly session_id?: string;
  readonly level: ThinkingLevel;
}

export interface ListModels {
  readonly type: "list_models";
  readonly id: string;
  readonly session_id?: string;
}

export type ClientMessage =
  | PairRequest
  | UserMessage
  | QueuedMessageSet
  | QueuedMessageClear
  | ApproveTool
  | Cancel
  | Ping
  | SessionSync
  | SessionNew
  | SessionCompact
  | ModelSet
  | ThinkingSet
  | ListModels;

export const SERVER_MESSAGE_TYPES = [
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
] as const;
export const SERVER_MESSAGE_DISCRIMINATORS = {
  pair_ok: "pair_ok",
  pair_error: "pair_error",
  user_input: "user_input",
  user_message: "user_message",
  queued_message_state: "queued_message_state",
  agent_chunk: "agent_chunk",
  agent_done: "agent_done",
  agent_message: "agent_message",
  compaction: "compaction",
  tool_request: "tool_request",
  tool_result: "tool_result",
  error: "error",
  cancelled: "cancelled",
  pong: "pong",
  bye: "bye",
  session_history: "session_history",
  action_ok: "action_ok",
  action_error: "action_error",
  models_list: "models_list",
} as const;
export type ServerMessageType = (typeof SERVER_MESSAGE_TYPES)[number];
export const SESSION_SCOPED_SERVER_MESSAGE_TYPES = [
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
] as const;
export const appPiServerTypes = SERVER_MESSAGE_TYPES;
export type AppPiServerType = ServerMessageType;

export interface PairOk {
  readonly type: "pair_ok";
  readonly in_reply_to: string;
  readonly session_name: string;
  readonly session_started_at: number;
  readonly session_id?: string;
  readonly room_id: string;
  readonly harness?: {
  readonly name: string;
  readonly version: string;
};
  readonly hostname?: string;
  readonly dh_pk?: string;
  readonly dh_sig?: string;
}

export interface PairError {
  readonly type: "pair_error";
  readonly in_reply_to: string;
  readonly code: PairErrorCode;
  readonly message: string;
}

export interface UserInput {
  readonly type: "user_input";
  readonly id: string;
  readonly session_id?: string;
  readonly text: string;
  readonly images?: Array<WireImage>;
  readonly streaming_behavior?: StreamingBehavior;
  readonly ts?: number;
}

export interface QueuedMessageState {
  readonly type: "queued_message_state";
  readonly session_id?: string;
  readonly id?: string;
  readonly text?: string;
}

export interface AgentChunk {
  readonly type: "agent_chunk";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly delta: string;
  readonly ts?: number;
}

export interface AgentDone {
  readonly type: "agent_done";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly usage?: Usage;
  readonly ts?: number;
}

export interface AgentMessage {
  readonly type: "agent_message";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly text: string;
  readonly usage?: Usage;
  readonly ts?: number;
  readonly message_id?: string;
}

export interface Compaction {
  readonly type: "compaction";
  readonly session_id?: string;
  readonly summary: string;
  readonly tokens_before: number;
  readonly ts?: number;
}

export interface ToolRequest {
  readonly type: "tool_request";
  readonly session_id?: string;
  readonly tool_call_id: string;
  readonly tool: string;
  readonly args: unknown;
}

export interface ToolResult {
  readonly type: "tool_result";
  readonly session_id?: string;
  readonly tool_call_id: string;
  readonly result?: unknown;
  readonly error?: string;
}

export interface ErrorMessage {
  readonly type: "error";
  readonly session_id?: string;
  readonly in_reply_to?: string;
  readonly code: ErrorCode;
  readonly message: string;
}

export interface Cancelled {
  readonly type: "cancelled";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly target_id: string;
}

export interface Pong {
  readonly type: "pong";
  readonly in_reply_to: string;
}

export interface Bye {
  readonly type: "bye";
  readonly reason: ByeReason;
}

export interface SessionHistory {
  readonly type: "session_history";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly session_started_at: number;
  readonly events: Array<SessionHistoryEvent>;
  readonly eos: boolean;
  readonly truncated: boolean;
}

export interface ActionOk {
  readonly type: "action_ok";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly action: ActionName;
}

export interface ActionError {
  readonly type: "action_error";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly action: ActionName;
  readonly error: string;
}

export interface ModelsList {
  readonly type: "models_list";
  readonly session_id?: string;
  readonly in_reply_to: string;
  readonly models: Array<WireModel>;
  readonly current?: WireModel;
}

export type ServerMessage =
  | PairOk
  | PairError
  | UserInput
  | UserMessage
  | QueuedMessageState
  | AgentChunk
  | AgentDone
  | AgentMessage
  | Compaction
  | ToolRequest
  | ToolResult
  | ErrorMessage
  | Cancelled
  | Pong
  | Bye
  | SessionHistory
  | ActionOk
  | ActionError
  | ModelsList;

export const relayControlTypes = [
  "hello",
  "auth",
  "challenge",
  "subscribe_presence",
  "unsubscribe_presence",
  "presence_check",
  "presence",
  "peer_online",
  "peer_offline",
  "subscribe_rooms",
  "unsubscribe_rooms",
  "rooms_check",
  "rooms",
  "room_announced",
  "room_ended",
  "room_meta_update",
  "room_meta_updated",
] as const;
export type RelayControlType = (typeof relayControlTypes)[number];

export interface RelayControlFrameHello {
  readonly type: "hello";
  readonly pubkey: string;
  readonly device_id: string;
  readonly room_id?: string;
  readonly room_meta?: {
  readonly name?: string;
  readonly cwd?: string;
  readonly model?: string;
  readonly thinking?: string;
  readonly session_id?: string;
  readonly working?: boolean;
};
}

export interface RelayControlFrameAuth {
  readonly type: "auth";
  readonly sig: string;
}

export interface RelayControlFrameChallenge {
  readonly type: "challenge";
  readonly nonce: string;
}

export interface RelayControlFrameSubscribePresence {
  readonly type: "subscribe_presence";
  readonly peers?: Array<string>;
}

export interface RelayControlFrameUnsubscribePresence {
  readonly type: "unsubscribe_presence";
  readonly peers?: Array<string>;
}

export interface RelayControlFramePresenceCheck {
  readonly type: "presence_check";
  readonly peers?: Array<string>;
}

export interface RelayControlFramePresence {
  readonly type: "presence";
  readonly states: Array<{
  readonly peer: string;
  readonly online: boolean;
  readonly since_ts?: number | null;
}>;
}

export interface RelayControlFramePeerOnline {
  readonly type: "peer_online";
  readonly peer: string;
}

export interface RelayControlFramePeerOffline {
  readonly type: "peer_offline";
  readonly peer: string;
  readonly since_ts: number;
}

export interface RelayControlFrameSubscribeRooms {
  readonly type: "subscribe_rooms";
  readonly peers?: Array<string>;
}

export interface RelayControlFrameUnsubscribeRooms {
  readonly type: "unsubscribe_rooms";
  readonly peers?: Array<string>;
}

export interface RelayControlFrameRoomsCheck {
  readonly type: "rooms_check";
  readonly peers?: Array<string>;
}

export interface RelayControlFrameRooms {
  readonly type: "rooms";
  readonly peer: string;
  readonly rooms: Array<{
  readonly room_id: string;
  readonly name?: string;
  readonly cwd?: string;
  readonly session_id?: string;
  readonly model?: string;
  readonly thinking?: string;
  readonly working: boolean;
  readonly started_at: number;
}>;
}

export interface RelayControlFrameRoomAnnounced {
  readonly type: "room_announced";
  readonly peer: string;
  readonly room_id: string;
  readonly name?: string;
  readonly cwd?: string;
  readonly session_id?: string;
  readonly model?: string;
  readonly thinking?: string;
  readonly working: boolean;
  readonly started_at: number;
}

export interface RelayControlFrameRoomEnded {
  readonly type: "room_ended";
  readonly peer: string;
  readonly room_id: string;
  readonly since_ts: number;
}

export interface RelayControlFrameRoomMetaUpdate {
  readonly type: "room_meta_update";
  readonly room_id?: string;
  readonly meta: {
  readonly model?: string | null;
  readonly thinking?: string | null;
  readonly session_id?: string | null;
  readonly working?: boolean;
};
}

export interface RelayControlFrameRoomMetaUpdated {
  readonly type: "room_meta_updated";
  readonly peer: string;
  readonly room_id: string;
  readonly meta: {
  readonly model?: string | null;
  readonly thinking?: string | null;
  readonly session_id?: string | null;
  readonly working?: boolean;
};
}

export type RelayControlFrame =
  | RelayControlFrameHello
  | RelayControlFrameAuth
  | RelayControlFrameChallenge
  | RelayControlFrameSubscribePresence
  | RelayControlFrameUnsubscribePresence
  | RelayControlFramePresenceCheck
  | RelayControlFramePresence
  | RelayControlFramePeerOnline
  | RelayControlFramePeerOffline
  | RelayControlFrameSubscribeRooms
  | RelayControlFrameUnsubscribeRooms
  | RelayControlFrameRoomsCheck
  | RelayControlFrameRooms
  | RelayControlFrameRoomAnnounced
  | RelayControlFrameRoomEnded
  | RelayControlFrameRoomMetaUpdate
  | RelayControlFrameRoomMetaUpdated;

export const crossPcTypes = [
  "pi_envelope",
  "pi_envelope_in",
] as const;
export type CrossPcType = (typeof crossPcTypes)[number];

export interface CrossPcFramePiEnvelope {
  readonly type: "pi_envelope";
  readonly to_pc: string;
  readonly to_room: string;
  readonly envelope: {
  readonly from: string;
  readonly to: string | Array<string>;
  readonly id: string;
  readonly re: string | null;
  readonly body: unknown;
};
}

export interface CrossPcFramePiEnvelopeIn {
  readonly type: "pi_envelope_in";
  readonly from_pc: string;
  readonly to_room: string;
  readonly envelope: {
  readonly from: "_relay";
  readonly to: string;
  readonly id: string;
  readonly re: string | null;
  readonly body: {
  readonly type: "transport_error";
  readonly reason: "offline" | "not_authorized" | "bad_envelope";
};
} | {
  readonly from: string;
  readonly to: string | Array<string>;
  readonly id: string;
  readonly re: string | null;
  readonly body: unknown;
};
}

export type CrossPcFrame =
  | CrossPcFramePiEnvelope
  | CrossPcFramePiEnvelopeIn;

export const cockpitControlTypes = [
  "prompt",
  "outpost_pi_control",
  "outpost-pi:relay-state",
  "outpost-pi:name-assigned",
  "outpost-pi:pair-code",
  "outpost-pi:paired",
  "outpost-pi:mesh-revoked",
] as const;
export type CockpitControlType = (typeof cockpitControlTypes)[number];

export interface CockpitControlFramePrompt {
  readonly type: "prompt";
  readonly message: string;
}

export interface CockpitControlFrameOutpostPiControl {
  readonly type: "outpost_pi_control";
  readonly command: "relay_on" | "relay_off" | "relay_toggle" | "relay_status" | "rename";
  readonly name?: string;
}

export interface CockpitControlFrameOutpostPiRelayState {
  readonly role: "custom";
  readonly customType: "outpost-pi:relay-state" | "outpost-pi:name-assigned" | "outpost-pi:pair-code" | "outpost-pi:paired" | "outpost-pi:mesh-revoked";
  readonly content: string;
  readonly details?: unknown;
  readonly display?: boolean;
}

export interface CockpitControlFrameOutpostPiNameAssigned {
  readonly role: "custom";
  readonly customType: "outpost-pi:relay-state" | "outpost-pi:name-assigned" | "outpost-pi:pair-code" | "outpost-pi:paired" | "outpost-pi:mesh-revoked";
  readonly content: string;
  readonly details?: unknown;
  readonly display?: boolean;
}

export interface CockpitControlFrameOutpostPiPairCode {
  readonly role: "custom";
  readonly customType: "outpost-pi:relay-state" | "outpost-pi:name-assigned" | "outpost-pi:pair-code" | "outpost-pi:paired" | "outpost-pi:mesh-revoked";
  readonly content: string;
  readonly details?: unknown;
  readonly display?: boolean;
}

export interface CockpitControlFrameOutpostPiPaired {
  readonly role: "custom";
  readonly customType: "outpost-pi:relay-state" | "outpost-pi:name-assigned" | "outpost-pi:pair-code" | "outpost-pi:paired" | "outpost-pi:mesh-revoked";
  readonly content: string;
  readonly details?: unknown;
  readonly display?: boolean;
}

export interface CockpitControlFrameOutpostPiMeshRevoked {
  readonly role: "custom";
  readonly customType: "outpost-pi:relay-state" | "outpost-pi:name-assigned" | "outpost-pi:pair-code" | "outpost-pi:paired" | "outpost-pi:mesh-revoked";
  readonly content: string;
  readonly details?: unknown;
  readonly display?: boolean;
}

export type CockpitControlFrame =
  | CockpitControlFramePrompt
  | CockpitControlFrameOutpostPiControl
  | CockpitControlFrameOutpostPiRelayState
  | CockpitControlFrameOutpostPiNameAssigned
  | CockpitControlFrameOutpostPiPairCode
  | CockpitControlFrameOutpostPiPaired
  | CockpitControlFrameOutpostPiMeshRevoked;

export const RELAY_SERVER_CONTROL_FRAME_TYPES = [
  "challenge",
  "presence",
  "peer_online",
  "peer_offline",
  "rooms",
  "room_announced",
  "room_ended",
  "room_meta_updated",
] as const;
export type RelayServerControlFrameType = (typeof RELAY_SERVER_CONTROL_FRAME_TYPES)[number];
export type RelayServerControlFrame = Extract<RelayControlFrame, { readonly type: RelayServerControlFrameType }>;
export const RELAY_POST_AUTH_CONTROL_FRAME_TYPES = [
  "presence",
  "peer_online",
  "peer_offline",
  "rooms",
  "room_announced",
  "room_ended",
  "room_meta_updated",
] as const;
export type RelayPostAuthControlFrameType = (typeof RELAY_POST_AUTH_CONTROL_FRAME_TYPES)[number];
export type RelayPostAuthControlFrame = Extract<RelayControlFrame, { readonly type: RelayPostAuthControlFrameType }>;

export const SESSION_HISTORY_EVENT_TYPES = [
  "user_input",
  "tool_request",
  "tool_result",
  "agent_message",
  "compaction",
] as const;
export type SessionHistoryEventType = (typeof SESSION_HISTORY_EVENT_TYPES)[number];

type ProtocolRecord = Record<string, unknown>;

type ProtocolValidator<T> = (value: unknown) => value is T;

function asRecord(value: unknown): ProtocolRecord | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? value as ProtocolRecord : undefined;
}

function hasOnlyKeys(record: ProtocolRecord, allowedKeys: readonly string[]): boolean {
  return Object.keys(record).every((key) => allowedKeys.includes(key));
}

function isObjectLike(value: unknown, allowedKeys: readonly string[] | undefined, validate: (record: ProtocolRecord) => boolean): boolean {
  const record = asRecord(value);
  return record !== undefined && (allowedKeys === undefined || hasOnlyKeys(record, allowedKeys)) && validate(record);
}

function isInteger(value: unknown): value is number {
  return Number.isInteger(value);
}

function isIntegerAtLeast(value: unknown, minimum: number): value is number {
  return isInteger(value) && value >= minimum;
}


export function isRelayOuterEnvelope(value: unknown): value is RelayOuterEnvelope {
  return isObjectLike(value, ["peer", "room", "ct"], (record) => ((Object.hasOwn(record, "peer") && (typeof record["peer"] === "string" && record["peer"].length >= 1)) && (Object.hasOwn(record, "room") && (typeof record["room"] === "string" && record["room"].length >= 1)) && (Object.hasOwn(record, "ct") && (typeof record["ct"] === "string" && record["ct"].length >= 1))));
}

export function isRelayOuterEnvelopeCompat(value: unknown): value is RelayOuterEnvelopeCompat {
  return isObjectLike(value, ["peer", "room", "ct"], (record) => ((Object.hasOwn(record, "peer") && (typeof record["peer"] === "string" && record["peer"].length >= 1)) && (record["room"] === undefined || (typeof record["room"] === "string" && record["room"].length >= 1)) && (Object.hasOwn(record, "ct") && (typeof record["ct"] === "string" && record["ct"].length >= 1))));
}

function isHistoryUserInput(value: unknown): value is HistoryUserInput {
  return isObjectLike(value, ["ts", "type", "id", "text", "images"], (record) => ((Object.hasOwn(record, "ts") && isIntegerAtLeast(record["ts"], 0)) && (Object.hasOwn(record, "type") && record["type"] === "user_input") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (Object.hasOwn(record, "text") && typeof record["text"] === "string") && (record["images"] === undefined || (Array.isArray(record["images"]) && record["images"].every((item) => isObjectLike(item, ["data", "mime"], (record) => ((Object.hasOwn(record, "data") && (typeof record["data"] === "string" && record["data"].length >= 1)) && (Object.hasOwn(record, "mime") && (typeof record["mime"] === "string" && record["mime"].length >= 1)))))))));
}

function isHistoryToolRequest(value: unknown): value is HistoryToolRequest {
  return isObjectLike(value, ["ts", "type", "tool_call_id", "tool", "args"], (record) => ((Object.hasOwn(record, "ts") && isIntegerAtLeast(record["ts"], 0)) && (Object.hasOwn(record, "type") && record["type"] === "tool_request") && (Object.hasOwn(record, "tool_call_id") && (typeof record["tool_call_id"] === "string" && record["tool_call_id"].length >= 1)) && (Object.hasOwn(record, "tool") && (typeof record["tool"] === "string" && record["tool"].length >= 1)) && (Object.hasOwn(record, "args") && true)));
}

function isHistoryToolResult(value: unknown): value is HistoryToolResult {
  return isObjectLike(value, ["ts", "type", "tool_call_id", "result", "error"], (record) => ((Object.hasOwn(record, "ts") && isIntegerAtLeast(record["ts"], 0)) && (Object.hasOwn(record, "type") && record["type"] === "tool_result") && (Object.hasOwn(record, "tool_call_id") && (typeof record["tool_call_id"] === "string" && record["tool_call_id"].length >= 1)) && (record["result"] === undefined || true) && (record["error"] === undefined || typeof record["error"] === "string")));
}

function isHistoryAgentMessage(value: unknown): value is HistoryAgentMessage {
  return isObjectLike(value, ["ts", "type", "in_reply_to", "text", "message_id", "usage"], (record) => ((Object.hasOwn(record, "ts") && isIntegerAtLeast(record["ts"], 0)) && (Object.hasOwn(record, "type") && record["type"] === "agent_message") && (Object.hasOwn(record, "in_reply_to") && (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1)) && (Object.hasOwn(record, "text") && typeof record["text"] === "string") && (record["message_id"] === undefined || typeof record["message_id"] === "string") && (record["usage"] === undefined || isObjectLike(record["usage"], ["input_tokens", "output_tokens"], (record) => ((Object.hasOwn(record, "input_tokens") && isIntegerAtLeast(record["input_tokens"], 0)) && (Object.hasOwn(record, "output_tokens") && isIntegerAtLeast(record["output_tokens"], 0)))))));
}

function isHistoryCompaction(value: unknown): value is HistoryCompaction {
  return isObjectLike(value, ["ts", "type", "summary", "tokens_before"], (record) => ((Object.hasOwn(record, "ts") && isIntegerAtLeast(record["ts"], 0)) && (Object.hasOwn(record, "type") && record["type"] === "compaction") && (Object.hasOwn(record, "summary") && typeof record["summary"] === "string") && (Object.hasOwn(record, "tokens_before") && isIntegerAtLeast(record["tokens_before"], 0))));
}

function isPairRequest(value: unknown): value is PairRequest {
  return isObjectLike(value, ["type", "id", "token_id", "pair_mac", "device_name", "dh_pk", "dh_sig"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "pair_request") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["token_id"] === undefined || (typeof record["token_id"] === "string" && record["token_id"].length >= 1)) && (record["pair_mac"] === undefined || (typeof record["pair_mac"] === "string" && record["pair_mac"].length >= 1)) && (Object.hasOwn(record, "device_name") && (typeof record["device_name"] === "string" && record["device_name"].length >= 1)) && (record["dh_pk"] === undefined || (typeof record["dh_pk"] === "string" && record["dh_pk"].length >= 1)) && (record["dh_sig"] === undefined || (typeof record["dh_sig"] === "string" && record["dh_sig"].length >= 1))));
}

function isUserMessage(value: unknown): value is UserMessage {
  return isObjectLike(value, ["type", "id", "session_id", "text", "images", "streaming_behavior", "ts"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "user_message") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "text") && typeof record["text"] === "string") && (record["images"] === undefined || (Array.isArray(record["images"]) && record["images"].every((item) => isObjectLike(item, ["data", "mime"], (record) => ((Object.hasOwn(record, "data") && (typeof record["data"] === "string" && record["data"].length >= 1)) && (Object.hasOwn(record, "mime") && (typeof record["mime"] === "string" && record["mime"].length >= 1))))))) && (record["streaming_behavior"] === undefined || record["streaming_behavior"] === "steer") && (record["ts"] === undefined || isIntegerAtLeast(record["ts"], 0))));
}

function isQueuedMessageSet(value: unknown): value is QueuedMessageSet {
  return isObjectLike(value, ["type", "id", "session_id", "text"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "queued_message_set") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "text") && typeof record["text"] === "string")));
}

function isQueuedMessageClear(value: unknown): value is QueuedMessageClear {
  return isObjectLike(value, ["type", "id", "session_id"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "queued_message_clear") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512))));
}

function isApproveTool(value: unknown): value is ApproveTool {
  return isObjectLike(value, ["type", "id", "session_id", "tool_call_id", "decision"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "approve_tool") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "tool_call_id") && (typeof record["tool_call_id"] === "string" && record["tool_call_id"].length >= 1)) && (Object.hasOwn(record, "decision") && (record["decision"] === "allow" || record["decision"] === "deny"))));
}

function isCancel(value: unknown): value is Cancel {
  return isObjectLike(value, ["type", "id", "session_id", "target_id"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "cancel") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "target_id") && (typeof record["target_id"] === "string" && record["target_id"].length >= 1))));
}

function isPing(value: unknown): value is Ping {
  return isObjectLike(value, ["type", "id"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "ping") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1))));
}

function isSessionSync(value: unknown): value is SessionSync {
  return isObjectLike(value, ["type", "id", "session_id", "limit"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "session_sync") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (record["limit"] === undefined || isIntegerAtLeast(record["limit"], 1))));
}

function isSessionNew(value: unknown): value is SessionNew {
  return isObjectLike(value, ["type", "id", "session_id"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "session_new") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512))));
}

function isSessionCompact(value: unknown): value is SessionCompact {
  return isObjectLike(value, ["type", "id", "session_id"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "session_compact") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512))));
}

function isModelSet(value: unknown): value is ModelSet {
  return isObjectLike(value, ["type", "id", "session_id", "provider", "model_id"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "model_set") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "provider") && (typeof record["provider"] === "string" && record["provider"].length >= 1)) && (Object.hasOwn(record, "model_id") && (typeof record["model_id"] === "string" && record["model_id"].length >= 1))));
}

function isThinkingSet(value: unknown): value is ThinkingSet {
  return isObjectLike(value, ["type", "id", "session_id", "level"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "thinking_set") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "level") && (record["level"] === "off" || record["level"] === "minimal" || record["level"] === "low" || record["level"] === "medium" || record["level"] === "high" || record["level"] === "xhigh"))));
}

function isListModels(value: unknown): value is ListModels {
  return isObjectLike(value, ["type", "id", "session_id"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "list_models") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512))));
}

function isPairOk(value: unknown): value is PairOk {
  return isObjectLike(value, ["type", "in_reply_to", "session_name", "session_started_at", "session_id", "room_id", "harness", "hostname", "dh_pk", "dh_sig"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "pair_ok") && (Object.hasOwn(record, "in_reply_to") && (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1)) && (Object.hasOwn(record, "session_name") && (typeof record["session_name"] === "string" && record["session_name"].length >= 1)) && (Object.hasOwn(record, "session_started_at") && isIntegerAtLeast(record["session_started_at"], 0)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "room_id") && (typeof record["room_id"] === "string" && record["room_id"].length >= 1)) && (record["harness"] === undefined || isObjectLike(record["harness"], ["name", "version"], (record) => ((Object.hasOwn(record, "name") && (typeof record["name"] === "string" && record["name"].length >= 1)) && (Object.hasOwn(record, "version") && (typeof record["version"] === "string" && record["version"].length >= 1))))) && (record["hostname"] === undefined || (typeof record["hostname"] === "string" && record["hostname"].length >= 1)) && (record["dh_pk"] === undefined || (typeof record["dh_pk"] === "string" && record["dh_pk"].length >= 1)) && (record["dh_sig"] === undefined || (typeof record["dh_sig"] === "string" && record["dh_sig"].length >= 1))));
}

function isPairError(value: unknown): value is PairError {
  return isObjectLike(value, ["type", "in_reply_to", "code", "message"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "pair_error") && (Object.hasOwn(record, "in_reply_to") && (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1)) && (Object.hasOwn(record, "code") && (record["code"] === "token_expired" || record["code"] === "token_consumed" || record["code"] === "token_unknown" || record["code"] === "bad_dh_sig" || record["code"] === "internal_error")) && (Object.hasOwn(record, "message") && typeof record["message"] === "string")));
}

function isUserInput(value: unknown): value is UserInput {
  return isObjectLike(value, ["type", "id", "session_id", "text", "images", "streaming_behavior", "ts"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "user_input") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "text") && typeof record["text"] === "string") && (record["images"] === undefined || (Array.isArray(record["images"]) && record["images"].every((item) => isObjectLike(item, ["data", "mime"], (record) => ((Object.hasOwn(record, "data") && (typeof record["data"] === "string" && record["data"].length >= 1)) && (Object.hasOwn(record, "mime") && (typeof record["mime"] === "string" && record["mime"].length >= 1))))))) && (record["streaming_behavior"] === undefined || record["streaming_behavior"] === "steer") && (record["ts"] === undefined || isIntegerAtLeast(record["ts"], 0))));
}

function isQueuedMessageState(value: unknown): value is QueuedMessageState {
  return isObjectLike(value, ["type", "session_id", "id", "text"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "queued_message_state") && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (record["id"] === undefined || (typeof record["id"] === "string" && record["id"].length >= 1)) && (record["text"] === undefined || typeof record["text"] === "string")));
}

function isAgentChunk(value: unknown): value is AgentChunk {
  return isObjectLike(value, ["type", "session_id", "in_reply_to", "delta", "ts"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "agent_chunk") && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "in_reply_to") && (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1)) && (Object.hasOwn(record, "delta") && typeof record["delta"] === "string") && (record["ts"] === undefined || isIntegerAtLeast(record["ts"], 0))));
}

function isAgentDone(value: unknown): value is AgentDone {
  return isObjectLike(value, ["type", "session_id", "in_reply_to", "usage", "ts"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "agent_done") && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "in_reply_to") && (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1)) && (record["usage"] === undefined || isObjectLike(record["usage"], ["input_tokens", "output_tokens"], (record) => ((Object.hasOwn(record, "input_tokens") && isIntegerAtLeast(record["input_tokens"], 0)) && (Object.hasOwn(record, "output_tokens") && isIntegerAtLeast(record["output_tokens"], 0))))) && (record["ts"] === undefined || isIntegerAtLeast(record["ts"], 0))));
}

function isAgentMessage(value: unknown): value is AgentMessage {
  return isObjectLike(value, ["type", "session_id", "in_reply_to", "text", "usage", "ts", "message_id"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "agent_message") && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "in_reply_to") && (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1)) && (Object.hasOwn(record, "text") && typeof record["text"] === "string") && (record["usage"] === undefined || isObjectLike(record["usage"], ["input_tokens", "output_tokens"], (record) => ((Object.hasOwn(record, "input_tokens") && isIntegerAtLeast(record["input_tokens"], 0)) && (Object.hasOwn(record, "output_tokens") && isIntegerAtLeast(record["output_tokens"], 0))))) && (record["ts"] === undefined || isIntegerAtLeast(record["ts"], 0)) && (record["message_id"] === undefined || typeof record["message_id"] === "string")));
}

function isCompaction(value: unknown): value is Compaction {
  return isObjectLike(value, ["type", "session_id", "summary", "tokens_before", "ts"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "compaction") && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "summary") && typeof record["summary"] === "string") && (Object.hasOwn(record, "tokens_before") && isIntegerAtLeast(record["tokens_before"], 0)) && (record["ts"] === undefined || isIntegerAtLeast(record["ts"], 0))));
}

function isToolRequest(value: unknown): value is ToolRequest {
  return isObjectLike(value, ["type", "session_id", "tool_call_id", "tool", "args"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "tool_request") && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "tool_call_id") && (typeof record["tool_call_id"] === "string" && record["tool_call_id"].length >= 1)) && (Object.hasOwn(record, "tool") && (typeof record["tool"] === "string" && record["tool"].length >= 1)) && (Object.hasOwn(record, "args") && true)));
}

function isToolResult(value: unknown): value is ToolResult {
  return isObjectLike(value, ["type", "session_id", "tool_call_id", "result", "error"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "tool_result") && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "tool_call_id") && (typeof record["tool_call_id"] === "string" && record["tool_call_id"].length >= 1)) && (record["result"] === undefined || true) && (record["error"] === undefined || typeof record["error"] === "string")));
}

function isErrorMessage(value: unknown): value is ErrorMessage {
  return isObjectLike(value, ["type", "session_id", "in_reply_to", "code", "message"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "error") && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (record["in_reply_to"] === undefined || (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1)) && (Object.hasOwn(record, "code") && (typeof record["code"] === "string" && record["code"].length >= 1)) && (Object.hasOwn(record, "message") && typeof record["message"] === "string")));
}

function isCancelled(value: unknown): value is Cancelled {
  return isObjectLike(value, ["type", "session_id", "in_reply_to", "target_id"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "cancelled") && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "in_reply_to") && (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1)) && (Object.hasOwn(record, "target_id") && (typeof record["target_id"] === "string" && record["target_id"].length >= 1))));
}

function isPong(value: unknown): value is Pong {
  return isObjectLike(value, ["type", "in_reply_to"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "pong") && (Object.hasOwn(record, "in_reply_to") && (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1))));
}

function isBye(value: unknown): value is Bye {
  return isObjectLike(value, ["type", "reason"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "bye") && (Object.hasOwn(record, "reason") && (record["reason"] === "peer_stop" || record["reason"] === "session_replaced" || record["reason"] === "shutdown"))));
}

function isSessionHistory(value: unknown): value is SessionHistory {
  return isObjectLike(value, ["type", "session_id", "in_reply_to", "session_started_at", "events", "eos", "truncated"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "session_history") && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "in_reply_to") && (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1)) && (Object.hasOwn(record, "session_started_at") && isIntegerAtLeast(record["session_started_at"], 0)) && (Object.hasOwn(record, "events") && (Array.isArray(record["events"]) && record["events"].every((item) => (isObjectLike(item, ["ts", "type", "id", "text", "images"], (record) => ((Object.hasOwn(record, "ts") && isIntegerAtLeast(record["ts"], 0)) && (Object.hasOwn(record, "type") && record["type"] === "user_input") && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (Object.hasOwn(record, "text") && typeof record["text"] === "string") && (record["images"] === undefined || (Array.isArray(record["images"]) && record["images"].every((item) => isObjectLike(item, ["data", "mime"], (record) => ((Object.hasOwn(record, "data") && (typeof record["data"] === "string" && record["data"].length >= 1)) && (Object.hasOwn(record, "mime") && (typeof record["mime"] === "string" && record["mime"].length >= 1))))))))) || isObjectLike(item, ["ts", "type", "tool_call_id", "tool", "args"], (record) => ((Object.hasOwn(record, "ts") && isIntegerAtLeast(record["ts"], 0)) && (Object.hasOwn(record, "type") && record["type"] === "tool_request") && (Object.hasOwn(record, "tool_call_id") && (typeof record["tool_call_id"] === "string" && record["tool_call_id"].length >= 1)) && (Object.hasOwn(record, "tool") && (typeof record["tool"] === "string" && record["tool"].length >= 1)) && (Object.hasOwn(record, "args") && true))) || isObjectLike(item, ["ts", "type", "tool_call_id", "result", "error"], (record) => ((Object.hasOwn(record, "ts") && isIntegerAtLeast(record["ts"], 0)) && (Object.hasOwn(record, "type") && record["type"] === "tool_result") && (Object.hasOwn(record, "tool_call_id") && (typeof record["tool_call_id"] === "string" && record["tool_call_id"].length >= 1)) && (record["result"] === undefined || true) && (record["error"] === undefined || typeof record["error"] === "string"))) || isObjectLike(item, ["ts", "type", "in_reply_to", "text", "message_id", "usage"], (record) => ((Object.hasOwn(record, "ts") && isIntegerAtLeast(record["ts"], 0)) && (Object.hasOwn(record, "type") && record["type"] === "agent_message") && (Object.hasOwn(record, "in_reply_to") && (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1)) && (Object.hasOwn(record, "text") && typeof record["text"] === "string") && (record["message_id"] === undefined || typeof record["message_id"] === "string") && (record["usage"] === undefined || isObjectLike(record["usage"], ["input_tokens", "output_tokens"], (record) => ((Object.hasOwn(record, "input_tokens") && isIntegerAtLeast(record["input_tokens"], 0)) && (Object.hasOwn(record, "output_tokens") && isIntegerAtLeast(record["output_tokens"], 0))))))) || isObjectLike(item, ["ts", "type", "summary", "tokens_before"], (record) => ((Object.hasOwn(record, "ts") && isIntegerAtLeast(record["ts"], 0)) && (Object.hasOwn(record, "type") && record["type"] === "compaction") && (Object.hasOwn(record, "summary") && typeof record["summary"] === "string") && (Object.hasOwn(record, "tokens_before") && isIntegerAtLeast(record["tokens_before"], 0)))))))) && (Object.hasOwn(record, "eos") && typeof record["eos"] === "boolean") && (Object.hasOwn(record, "truncated") && typeof record["truncated"] === "boolean")));
}

function isActionOk(value: unknown): value is ActionOk {
  return isObjectLike(value, ["type", "session_id", "in_reply_to", "action"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "action_ok") && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "in_reply_to") && (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1)) && (Object.hasOwn(record, "action") && (record["action"] === "session_new" || record["action"] === "session_compact" || record["action"] === "model_set" || record["action"] === "thinking_set"))));
}

function isActionError(value: unknown): value is ActionError {
  return isObjectLike(value, ["type", "session_id", "in_reply_to", "action", "error"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "action_error") && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "in_reply_to") && (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1)) && (Object.hasOwn(record, "action") && (record["action"] === "session_new" || record["action"] === "session_compact" || record["action"] === "model_set" || record["action"] === "thinking_set")) && (Object.hasOwn(record, "error") && typeof record["error"] === "string")));
}

function isModelsList(value: unknown): value is ModelsList {
  return isObjectLike(value, ["type", "session_id", "in_reply_to", "models", "current"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "models_list") && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (Object.hasOwn(record, "in_reply_to") && (typeof record["in_reply_to"] === "string" && record["in_reply_to"].length >= 1)) && (Object.hasOwn(record, "models") && (Array.isArray(record["models"]) && record["models"].every((item) => isObjectLike(item, ["id", "name", "provider", "reasoning", "context_window", "vision"], (record) => ((Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (Object.hasOwn(record, "name") && (typeof record["name"] === "string" && record["name"].length >= 1)) && (Object.hasOwn(record, "provider") && (typeof record["provider"] === "string" && record["provider"].length >= 1)) && (Object.hasOwn(record, "reasoning") && typeof record["reasoning"] === "boolean") && (Object.hasOwn(record, "context_window") && isIntegerAtLeast(record["context_window"], 0)) && (record["vision"] === undefined || typeof record["vision"] === "boolean")))))) && (record["current"] === undefined || isObjectLike(record["current"], ["id", "name", "provider", "reasoning", "context_window", "vision"], (record) => ((Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (Object.hasOwn(record, "name") && (typeof record["name"] === "string" && record["name"].length >= 1)) && (Object.hasOwn(record, "provider") && (typeof record["provider"] === "string" && record["provider"].length >= 1)) && (Object.hasOwn(record, "reasoning") && typeof record["reasoning"] === "boolean") && (Object.hasOwn(record, "context_window") && isIntegerAtLeast(record["context_window"], 0)) && (record["vision"] === undefined || typeof record["vision"] === "boolean"))))));
}

function isRelayControlFrameChallenge(value: unknown): value is RelayControlFrameChallenge {
  return isObjectLike(value, ["type", "nonce"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "challenge") && (Object.hasOwn(record, "nonce") && (typeof record["nonce"] === "string" && record["nonce"].length >= 1))));
}

function isRelayControlFramePresence(value: unknown): value is RelayControlFramePresence {
  return isObjectLike(value, ["type", "states"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "presence") && (Object.hasOwn(record, "states") && (Array.isArray(record["states"]) && record["states"].every((item) => isObjectLike(item, ["peer", "online", "since_ts"], (record) => ((Object.hasOwn(record, "peer") && (typeof record["peer"] === "string" && record["peer"].length >= 1)) && (Object.hasOwn(record, "online") && typeof record["online"] === "boolean") && (record["since_ts"] === undefined || (isIntegerAtLeast(record["since_ts"], 0) || record["since_ts"] === null)))))))));
}

function isRelayControlFramePeerOnline(value: unknown): value is RelayControlFramePeerOnline {
  return isObjectLike(value, ["type", "peer"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "peer_online") && (Object.hasOwn(record, "peer") && (typeof record["peer"] === "string" && record["peer"].length >= 1))));
}

function isRelayControlFramePeerOffline(value: unknown): value is RelayControlFramePeerOffline {
  return isObjectLike(value, ["type", "peer", "since_ts"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "peer_offline") && (Object.hasOwn(record, "peer") && (typeof record["peer"] === "string" && record["peer"].length >= 1)) && (Object.hasOwn(record, "since_ts") && isIntegerAtLeast(record["since_ts"], 0))));
}

function isRelayControlFrameRooms(value: unknown): value is RelayControlFrameRooms {
  return isObjectLike(value, ["type", "peer", "rooms"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "rooms") && (Object.hasOwn(record, "peer") && (typeof record["peer"] === "string" && record["peer"].length >= 1)) && (Object.hasOwn(record, "rooms") && (Array.isArray(record["rooms"]) && record["rooms"].every((item) => isObjectLike(item, ["room_id", "name", "cwd", "session_id", "model", "thinking", "working", "started_at"], (record) => ((Object.hasOwn(record, "room_id") && (typeof record["room_id"] === "string" && record["room_id"].length >= 1 && record["room_id"].length <= 256)) && (record["name"] === undefined || (typeof record["name"] === "string" && record["name"].length <= 256)) && (record["cwd"] === undefined || (typeof record["cwd"] === "string" && record["cwd"].length <= 4096)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (record["model"] === undefined || (typeof record["model"] === "string" && record["model"].length <= 256)) && (record["thinking"] === undefined || (typeof record["thinking"] === "string" && record["thinking"].length <= 32)) && (Object.hasOwn(record, "working") && typeof record["working"] === "boolean") && (Object.hasOwn(record, "started_at") && isIntegerAtLeast(record["started_at"], 0)))))))));
}

function isRelayControlFrameRoomAnnounced(value: unknown): value is RelayControlFrameRoomAnnounced {
  return isObjectLike(value, ["type", "peer", "room_id", "name", "cwd", "session_id", "model", "thinking", "working", "started_at"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "room_announced") && (Object.hasOwn(record, "peer") && (typeof record["peer"] === "string" && record["peer"].length >= 1)) && (Object.hasOwn(record, "room_id") && (typeof record["room_id"] === "string" && record["room_id"].length >= 1 && record["room_id"].length <= 256)) && (record["name"] === undefined || (typeof record["name"] === "string" && record["name"].length <= 256)) && (record["cwd"] === undefined || (typeof record["cwd"] === "string" && record["cwd"].length <= 4096)) && (record["session_id"] === undefined || (typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512)) && (record["model"] === undefined || (typeof record["model"] === "string" && record["model"].length <= 256)) && (record["thinking"] === undefined || (typeof record["thinking"] === "string" && record["thinking"].length <= 32)) && (Object.hasOwn(record, "working") && typeof record["working"] === "boolean") && (Object.hasOwn(record, "started_at") && isIntegerAtLeast(record["started_at"], 0))));
}

function isRelayControlFrameRoomEnded(value: unknown): value is RelayControlFrameRoomEnded {
  return isObjectLike(value, ["type", "peer", "room_id", "since_ts"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "room_ended") && (Object.hasOwn(record, "peer") && (typeof record["peer"] === "string" && record["peer"].length >= 1)) && (Object.hasOwn(record, "room_id") && (typeof record["room_id"] === "string" && record["room_id"].length >= 1 && record["room_id"].length <= 256)) && (Object.hasOwn(record, "since_ts") && isIntegerAtLeast(record["since_ts"], 0))));
}

function isRelayControlFrameRoomMetaUpdated(value: unknown): value is RelayControlFrameRoomMetaUpdated {
  return isObjectLike(value, ["type", "peer", "room_id", "meta"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "room_meta_updated") && (Object.hasOwn(record, "peer") && (typeof record["peer"] === "string" && record["peer"].length >= 1)) && (Object.hasOwn(record, "room_id") && (typeof record["room_id"] === "string" && record["room_id"].length >= 1 && record["room_id"].length <= 256)) && (Object.hasOwn(record, "meta") && isObjectLike(record["meta"], ["model", "thinking", "session_id", "working"], (record) => ((record["model"] === undefined || ((typeof record["model"] === "string" && record["model"].length <= 256) || record["model"] === null)) && (record["thinking"] === undefined || ((typeof record["thinking"] === "string" && record["thinking"].length <= 32) || record["thinking"] === null)) && (record["session_id"] === undefined || ((typeof record["session_id"] === "string" && record["session_id"].length >= 1 && record["session_id"].length <= 512) || record["session_id"] === null)) && (record["working"] === undefined || typeof record["working"] === "boolean"))))));
}

function isCrossPcFramePiEnvelope(value: unknown): value is CrossPcFramePiEnvelope {
  return isObjectLike(value, ["type", "to_pc", "to_room", "envelope"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "pi_envelope") && (Object.hasOwn(record, "to_pc") && (typeof record["to_pc"] === "string" && record["to_pc"].length >= 1)) && (Object.hasOwn(record, "to_room") && (typeof record["to_room"] === "string" && record["to_room"].length >= 1)) && (Object.hasOwn(record, "envelope") && isObjectLike(record["envelope"], ["from", "to", "id", "re", "body"], (record) => ((Object.hasOwn(record, "from") && (typeof record["from"] === "string" && record["from"].length >= 1)) && (Object.hasOwn(record, "to") && ((typeof record["to"] === "string" && record["to"].length >= 1) || (Array.isArray(record["to"]) && record["to"].length >= 1 && record["to"].every((item) => (typeof item === "string" && item.length >= 1))))) && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (Object.hasOwn(record, "re") && ((typeof record["re"] === "string" && record["re"].length >= 1) || record["re"] === null)) && (Object.hasOwn(record, "body") && true))))));
}

function isCrossPcFramePiEnvelopeIn(value: unknown): value is CrossPcFramePiEnvelopeIn {
  return isObjectLike(value, ["type", "from_pc", "to_room", "envelope"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "pi_envelope_in") && (Object.hasOwn(record, "from_pc") && (typeof record["from_pc"] === "string" && record["from_pc"].length >= 1)) && (Object.hasOwn(record, "to_room") && (typeof record["to_room"] === "string" && record["to_room"].length >= 1)) && (Object.hasOwn(record, "envelope") && (isObjectLike(record["envelope"], ["from", "to", "id", "re", "body"], (record) => ((Object.hasOwn(record, "from") && record["from"] === "_relay") && (Object.hasOwn(record, "to") && (typeof record["to"] === "string" && record["to"].length >= 1)) && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (Object.hasOwn(record, "re") && ((typeof record["re"] === "string" && record["re"].length >= 1) || record["re"] === null)) && (Object.hasOwn(record, "body") && isObjectLike(record["body"], ["type", "reason"], (record) => ((Object.hasOwn(record, "type") && record["type"] === "transport_error") && (Object.hasOwn(record, "reason") && (record["reason"] === "offline" || record["reason"] === "not_authorized" || record["reason"] === "bad_envelope"))))))) || isObjectLike(record["envelope"], ["from", "to", "id", "re", "body"], (record) => ((Object.hasOwn(record, "from") && (typeof record["from"] === "string" && record["from"].length >= 1)) && (Object.hasOwn(record, "to") && ((typeof record["to"] === "string" && record["to"].length >= 1) || (Array.isArray(record["to"]) && record["to"].length >= 1 && record["to"].every((item) => (typeof item === "string" && item.length >= 1))))) && (Object.hasOwn(record, "id") && (typeof record["id"] === "string" && record["id"].length >= 1)) && (Object.hasOwn(record, "re") && ((typeof record["re"] === "string" && record["re"].length >= 1) || record["re"] === null)) && (Object.hasOwn(record, "body") && true)))))));
}

const SESSION_HISTORY_EVENT_VALIDATORS: { readonly [K in SessionHistoryEventType]: ProtocolValidator<Extract<SessionHistoryEvent, { readonly type: K }>> } = {
  "user_input": isHistoryUserInput,
  "tool_request": isHistoryToolRequest,
  "tool_result": isHistoryToolResult,
  "agent_message": isHistoryAgentMessage,
  "compaction": isHistoryCompaction,
};

export function isSessionHistoryEvent(value: unknown): value is SessionHistoryEvent {
  const record = asRecord(value);
  if (!record || typeof record["type"] !== "string") return false;
  const validate = SESSION_HISTORY_EVENT_VALIDATORS[record["type"] as SessionHistoryEventType];
  return validate?.(record) ?? false;
}

const CLIENT_MESSAGE_VALIDATORS: { readonly [K in ClientMessageType]: ProtocolValidator<Extract<ClientMessage, { readonly type: K }>> } = {
  "pair_request": isPairRequest,
  "user_message": isUserMessage,
  "queued_message_set": isQueuedMessageSet,
  "queued_message_clear": isQueuedMessageClear,
  "approve_tool": isApproveTool,
  "cancel": isCancel,
  "ping": isPing,
  "session_sync": isSessionSync,
  "session_new": isSessionNew,
  "session_compact": isSessionCompact,
  "model_set": isModelSet,
  "thinking_set": isThinkingSet,
  "list_models": isListModels,
};

export function isClientMessage(value: unknown): value is ClientMessage {
  const record = asRecord(value);
  if (!record || typeof record["type"] !== "string") return false;
  const validate = CLIENT_MESSAGE_VALIDATORS[record["type"] as ClientMessageType];
  return validate?.(record) ?? false;
}

const SERVER_MESSAGE_VALIDATORS: { readonly [K in ServerMessageType]: ProtocolValidator<Extract<ServerMessage, { readonly type: K }>> } = {
  "pair_ok": isPairOk,
  "pair_error": isPairError,
  "user_input": isUserInput,
  "user_message": isUserMessage,
  "queued_message_state": isQueuedMessageState,
  "agent_chunk": isAgentChunk,
  "agent_done": isAgentDone,
  "agent_message": isAgentMessage,
  "compaction": isCompaction,
  "tool_request": isToolRequest,
  "tool_result": isToolResult,
  "error": isErrorMessage,
  "cancelled": isCancelled,
  "pong": isPong,
  "bye": isBye,
  "session_history": isSessionHistory,
  "action_ok": isActionOk,
  "action_error": isActionError,
  "models_list": isModelsList,
};

export function isServerMessage(value: unknown): value is ServerMessage {
  const record = asRecord(value);
  if (!record || typeof record["type"] !== "string") return false;
  const validate = SERVER_MESSAGE_VALIDATORS[record["type"] as ServerMessageType];
  return validate?.(record) ?? false;
}

const CROSS_PC_FRAME_VALIDATORS: { readonly [K in CrossPcType]: ProtocolValidator<Extract<CrossPcFrame, { readonly type: K }>> } = {
  "pi_envelope": isCrossPcFramePiEnvelope,
  "pi_envelope_in": isCrossPcFramePiEnvelopeIn,
};

export function isCrossPcFrame(value: unknown): value is CrossPcFrame {
  const record = asRecord(value);
  if (!record || typeof record["type"] !== "string") return false;
  const validate = CROSS_PC_FRAME_VALIDATORS[record["type"] as CrossPcType];
  return validate?.(record) ?? false;
}

const RELAY_SERVER_CONTROL_FRAME_VALIDATORS: { readonly [K in RelayServerControlFrameType]: ProtocolValidator<Extract<RelayServerControlFrame, { readonly type: K }>> } = {
  "challenge": isRelayControlFrameChallenge,
  "presence": isRelayControlFramePresence,
  "peer_online": isRelayControlFramePeerOnline,
  "peer_offline": isRelayControlFramePeerOffline,
  "rooms": isRelayControlFrameRooms,
  "room_announced": isRelayControlFrameRoomAnnounced,
  "room_ended": isRelayControlFrameRoomEnded,
  "room_meta_updated": isRelayControlFrameRoomMetaUpdated,
};

export function isRelayServerControlFrame(value: unknown): value is RelayServerControlFrame {
  const record = asRecord(value);
  if (!record || typeof record["type"] !== "string") return false;
  const validate = RELAY_SERVER_CONTROL_FRAME_VALIDATORS[record["type"] as RelayServerControlFrameType];
  return validate?.(record) ?? false;
}

const RELAY_POST_AUTH_CONTROL_FRAME_VALIDATORS: { readonly [K in RelayPostAuthControlFrameType]: ProtocolValidator<Extract<RelayPostAuthControlFrame, { readonly type: K }>> } = {
  "presence": isRelayControlFramePresence,
  "peer_online": isRelayControlFramePeerOnline,
  "peer_offline": isRelayControlFramePeerOffline,
  "rooms": isRelayControlFrameRooms,
  "room_announced": isRelayControlFrameRoomAnnounced,
  "room_ended": isRelayControlFrameRoomEnded,
  "room_meta_updated": isRelayControlFrameRoomMetaUpdated,
};

export function isRelayPostAuthControlFrame(value: unknown): value is RelayPostAuthControlFrame {
  const record = asRecord(value);
  if (!record || typeof record["type"] !== "string") return false;
  const validate = RELAY_POST_AUTH_CONTROL_FRAME_VALIDATORS[record["type"] as RelayPostAuthControlFrameType];
  return validate?.(record) ?? false;
}

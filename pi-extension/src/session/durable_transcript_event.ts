import type { JsonValue } from "../protocol/generated/protocol.generated.js";
import type { TranscriptEvent } from "./transcript_event.js";

/**
 * Keep the SDK session custom-entry envelope extension-local.
 *
 * This is a persistence adapter format, not app↔Pi wire data: the shared
 * `TranscriptEvent` union remains the semantic authority, while this module is
 * the sole JSON codec and validator at the SDK custom-entry boundary. Keeping
 * the SDK storage envelope out of protocol codegen prevents a private session
 * file shape from becoming a cross-component wire contract. Move it into the
 * schema/codegen pipeline if another component must read or write these custom
 * entries, or if the persisted format becomes shared across implementations;
 * add an explicit v2 migration before changing the v1 shape.
 */
export const TRANSCRIPT_EVENT_CUSTOM_TYPE = "outpost-pi.transcript-event.v1" as const;

/** Prefix used to distinguish unsupported durable transcript versions from unrelated custom entries. */
export const TRANSCRIPT_EVENT_CUSTOM_TYPE_PREFIX = "outpost-pi.transcript-event.v" as const;

/** Classify one SDK context entry without treating future versions as v1. */
export type DurableTranscriptEventDecode =
  | { status: "decoded"; event: TranscriptEvent }
  | { status: "not_transcript" }
  | { status: "unsupported_version" }
  | { status: "invalid" };

type JsonRecord = { [key: string]: JsonValue };

const COMMON_KEYS = ["kind", "eventId", "sessionId", "ts", "turnId"] as const;

/**
 * Validate and clone a canonical event into the JSON-safe v1 payload written to the SDK session.
 *
 * @throws Error when the event is invalid or contains a value that cannot cross
 * the JSON persistence boundary, such as a non-finite number, unsupported
 * value, or cyclic structure. Validation is synchronous and runs before the
 * event can become durable or visible.
 */
export function encodeDurableTranscriptEventV1(event: TranscriptEvent): JsonValue {
  if (!isTranscriptEvent(event)) throw new Error("invalid durable transcript event");
  return cloneJsonValue(event);
}

/** Decode a custom SDK entry at the durable transcript boundary. */
export function decodeDurableTranscriptEntry(entry: unknown): DurableTranscriptEventDecode {
  try {
    if (!isRecord(entry) || typeof entry["customType"] !== "string") {
      return { status: "not_transcript" };
    }
    const customType = entry["customType"];
    if (customType !== TRANSCRIPT_EVENT_CUSTOM_TYPE) {
      return customType.startsWith(TRANSCRIPT_EVENT_CUSTOM_TYPE_PREFIX)
        ? { status: "unsupported_version" }
        : { status: "not_transcript" };
    }
    if (entry["type"] !== "custom") return { status: "invalid" };
    const data = entry["data"];
    if (!isTranscriptEvent(data)) return { status: "invalid" };
    return { status: "decoded", event: cloneJsonValue(data) as unknown as TranscriptEvent };
  } catch {
    return { status: "invalid" };
  }
}

function isTranscriptEvent(value: unknown): value is TranscriptEvent {
  if (!hasCommonFields(value)) return false;
  switch (value.kind) {
    case "user_submitted":
      return hasExactKeys(value, ...COMMON_KEYS, "clientMessageId", "text", "images")
        && isString(value["clientMessageId"])
        && isString(value["text"])
        && isOptionalImages(value["images"]);
    case "user_confirmed":
      return hasExactKeys(value, ...COMMON_KEYS, "clientMessageId", "text", "images", "streamingBehavior")
        && isString(value["clientMessageId"])
        && isString(value["text"])
        && isOptionalImages(value["images"])
        && (value["streamingBehavior"] === undefined || value["streamingBehavior"] === "steer");
    case "user_failed":
      return hasExactKeys(value, ...COMMON_KEYS, "clientMessageId", "code", "message")
        && isString(value["clientMessageId"])
        && isString(value["code"])
        && isString(value["message"]);
    case "assistant_delta":
      return hasExactKeys(value, ...COMMON_KEYS, "replyTo", "delta")
        && isString(value["replyTo"])
        && isString(value["delta"]);
    case "assistant_committed":
      return hasExactKeys(value, ...COMMON_KEYS, "messageId", "replyTo", "text", "usage")
        && isString(value["messageId"])
        && isString(value["replyTo"])
        && isString(value["text"])
        && isOptionalUsage(value["usage"]);
    case "assistant_done":
      return hasExactKeys(value, ...COMMON_KEYS, "replyTo", "usage")
        && isString(value["replyTo"])
        && isOptionalUsage(value["usage"]);
    case "provider_error":
      return hasExactKeys(value, ...COMMON_KEYS, "replyTo", "code", "message")
        && (value["replyTo"] === undefined || isString(value["replyTo"]))
        && isString(value["code"])
        && isString(value["message"]);
    case "tool_requested":
      return hasExactKeys(value, ...COMMON_KEYS, "toolCallId", "tool", "args")
        && isString(value["toolCallId"])
        && isString(value["tool"])
        && isRecord(value["args"])
        && isJsonValue(value["args"]);
    case "tool_finished":
      return hasExactKeys(value, ...COMMON_KEYS, "toolCallId", "result", "error")
        && isString(value["toolCallId"])
        && (value["result"] === undefined || isJsonValue(value["result"]))
        && (value["error"] === undefined || isString(value["error"]));
    case "compaction_recorded":
      return hasExactKeys(value, ...COMMON_KEYS, "summary", "tokensBefore")
        && isString(value["summary"])
        && (value["tokensBefore"] === undefined || isFiniteNonNegative(value["tokensBefore"]));
    default:
      return assertNever(value.kind);
  }
}

function hasCommonFields(value: unknown): value is Record<string, unknown> & Pick<TranscriptEvent, "kind" | "eventId" | "sessionId" | "ts"> {
  if (!isRecord(value) || Object.values(value).some((child) => child === undefined)) return false;
  if (!isNonEmptyString(value["kind"]) || !isNonEmptyString(value["eventId"]) || !isNonEmptyString(value["sessionId"])) {
    return false;
  }
  if (!isSafeTimestamp(value["ts"])) return false;
  return value["turnId"] === undefined || isNonEmptyString(value["turnId"]);
}

function hasExactKeys(value: Record<string, unknown>, ...allowed: readonly string[]): boolean {
  const keys = Reflect.ownKeys(value);
  return keys.every((key) => typeof key === "string" && allowed.includes(key));
}

function isOptionalImages(value: unknown): boolean {
  if (value === undefined) return true;
  return Array.isArray(value) && value.every((image) =>
    isRecord(image)
    && hasExactKeys(image, "data", "mime")
    && isString(image["data"])
    && isString(image["mime"])
  );
}

function isOptionalUsage(value: unknown): boolean {
  if (value === undefined) return true;
  return isRecord(value)
    && hasExactKeys(value, "input_tokens", "output_tokens")
    && isFiniteNonNegative(value["input_tokens"])
    && isFiniteNonNegative(value["output_tokens"]);
}

function isJsonValue(value: unknown, ancestors = new Set<object>()): value is JsonValue {
  if (value === null || typeof value === "string" || typeof value === "boolean") return true;
  if (typeof value === "number") return Number.isFinite(value);
  if (typeof value !== "object") return false;
  if (ancestors.has(value)) return false;
  ancestors.add(value);
  let valid: boolean;
  if (Array.isArray(value)) {
    valid = value.every((item) => isJsonValue(item, ancestors));
  } else if (isRecord(value)) {
    valid = Reflect.ownKeys(value).every((key) =>
      typeof key === "string" && isJsonValue(value[key], ancestors)
    );
  } else {
    valid = false;
  }
  ancestors.delete(value);
  return valid;
}

function cloneJsonValue(value: unknown): JsonValue {
  if (value === null || typeof value === "string" || typeof value === "boolean" || typeof value === "number") {
    return value;
  }
  if (Array.isArray(value)) return value.map(cloneJsonValue);
  const clone: JsonRecord = {};
  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    Object.defineProperty(clone, key, {
      value: cloneJsonValue(child),
      enumerable: true,
      configurable: true,
      writable: true,
    });
  }
  return clone;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function isString(value: unknown): value is string {
  return typeof value === "string";
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

function isSafeTimestamp(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}

function isFiniteNonNegative(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0;
}

function assertNever(value: never): false {
  void value;
  return false;
}

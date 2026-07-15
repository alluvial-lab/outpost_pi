import {
  CLIENT_MESSAGE_TYPES,
  SERVER_MESSAGE_TYPES,
  isClientMessage,
  isServerMessage,
} from "./generated/protocol.generated.js";
import type { ClientMessage, ServerMessage } from "./types.js";

/** Report an invalid JSON/message shape or a message type outside the generated allowlist. */
export class DecodeError extends Error {
  constructor(
    public readonly code: "invalid_message" | "unsupported_type",
    message: string,
  ) {
    super(message);
    this.name = "DecodeError";
  }
}

/** Encode one validated client message as a newline-delimited JSON frame. */
export function encodeClient(msg: ClientMessage): string {
  return JSON.stringify(msg) + "\n";
}

/**
 * Decode a server frame against the generated allowlist.
 *
 * @throws {@link DecodeError} when JSON, shape, or type validation fails.
 */
export function decodeServer(line: string): ServerMessage {
  const obj = parseJsonLine(line);
  const type = readType(obj);
  if (!SERVER_MESSAGE_TYPES.includes(type as ServerMessage["type"])) {
    throw new DecodeError("unsupported_type", `unknown type: ${type}`);
  }
  if (!isServerMessage(obj)) {
    throw new DecodeError("invalid_message", `invalid server message: ${type}`);
  }
  return obj;
}

/**
 * Decode a client frame against the generated allowlist.
 *
 * @throws {@link DecodeError} when JSON, shape, or type validation fails.
 */
export function decodeClient(line: string): ClientMessage {
  const obj = parseJsonLine(line);
  const type = readType(obj);
  if (!CLIENT_MESSAGE_TYPES.includes(type as ClientMessage["type"])) {
    throw new DecodeError("unsupported_type", `unknown type: ${type}`);
  }
  if (!isClientMessage(obj)) {
    throw new DecodeError("invalid_message", `invalid client message: ${type}`);
  }
  return obj;
}

function parseJsonLine(line: string): unknown {
  try {
    return JSON.parse(line.trim());
  } catch (e) {
    throw new DecodeError("invalid_message", `not JSON: ${(e as Error).message}`);
  }
}

function readType(obj: unknown): string {
  if (!obj || typeof obj !== "object") {
    throw new DecodeError("invalid_message", "missing 'type'");
  }
  const type = (obj as Record<string, unknown>).type;
  if (typeof type !== "string") {
    throw new DecodeError("invalid_message", "missing 'type'");
  }
  return type;
}

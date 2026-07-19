import { decodeClient } from "./codec.js";
import type { ClientMessage } from "./types.js";
import type {
  CrossPcFramePiEnvelopeIn,
  RelayControlFrame,
  RelayControlFrameChallenge,
} from "./generated/protocol.generated.js";

/** Endpoint-owned decoded payload ceiling; relay deployment overrides do not raise this value. */
export const RELAY_DEFAULT_MAX_DECODED_BYTES = 4 * 1024 * 1024;
/** JSON and routing overhead permitted beyond the encoded payload. */
export const RELAY_MAX_FRAME_OVERHEAD_BYTES = 64 * 1024;
/** Complete WebSocket message ceiling derived from the endpoint payload limit. */
export const RELAY_MAX_RAW_MESSAGE_BYTES =
  4 * Math.ceil(RELAY_DEFAULT_MAX_DECODED_BYTES / 3) + RELAY_MAX_FRAME_OVERHEAD_BYTES;
/** Smaller ceiling for unauthenticated challenge traffic. */
export const RELAY_MAX_PRE_AUTH_FRAME_BYTES = 16 * 1024;

/** Relay outer envelope validated before its payload enters app-message decoding. */
export interface RelayOuterEnvelope {
  readonly peer: string;
  readonly room?: string;
  readonly ct: string;
}

/** Relay-to-endpoint control variants consumed after authentication. */
export type RelayServerControlFrame = Extract<
  RelayControlFrame,
  { readonly type:
    | "presence"
    | "peer_online"
    | "peer_offline"
    | "rooms"
    | "room_announced"
    | "room_ended" }
>;

/** Limits applied before JSON and base64 allocation at relay ingress. */
export interface RelayIngressLimits {
  readonly maxRawBytes: number;
  readonly maxDecodedPayloadBytes: number;
}

/** One typed relay frame after boundary validation and, for outer envelopes, payload decoding. */
export type DecodedRelayIngress =
  | {
      readonly kind: "outer";
      readonly frame: RelayOuterEnvelope;
      readonly payloadUtf8: string;
    }
  | { readonly kind: "control"; readonly frame: RelayServerControlFrame }
  | { readonly kind: "cross_pc"; readonly frame: CrossPcFramePiEnvelopeIn };

/** Content-free relay ingress rejection surfaced to transport diagnostics. */
export class RelayIngressDecodeError extends Error {
  constructor(
    public readonly code: "too_large" | "invalid_message" | "unsupported_type",
    public readonly observedBytes: number,
  ) {
    super(`relay ingress rejected: ${code} (${observedBytes} bytes)`);
    this.name = "RelayIngressDecodeError";
  }
}

const DEFAULT_LIMITS: RelayIngressLimits = {
  maxRawBytes: RELAY_MAX_RAW_MESSAGE_BYTES,
  maxDecodedPayloadBytes: RELAY_DEFAULT_MAX_DECODED_BYTES,
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

function hasOptionalString(record: Record<string, unknown>, key: string): boolean {
  return record[key] === undefined || typeof record[key] === "string";
}

function isRoom(value: unknown): boolean {
  if (!isRecord(value)) return false;
  return isNonEmptyString(value.room_id) &&
    Number.isInteger(value.started_at) &&
    typeof value.working === "boolean" &&
    ["name", "cwd", "session_id", "model", "thinking"].every((key) =>
      hasOptionalString(value, key),
    );
}

function parseServerControl(value: Record<string, unknown>): RelayServerControlFrame | null {
  switch (value.type) {
    case "peer_online":
      return isNonEmptyString(value.peer)
        ? value as unknown as Extract<RelayServerControlFrame, { type: "peer_online" }>
        : null;
    case "peer_offline":
      return isNonEmptyString(value.peer) && Number.isFinite(value.since_ts)
        ? value as unknown as Extract<RelayServerControlFrame, { type: "peer_offline" }>
        : null;
    case "presence":
      if (!Array.isArray(value.states) || !value.states.every((state) =>
        isRecord(state) &&
        isNonEmptyString(state.peer) &&
        typeof state.online === "boolean" &&
        (state.since_ts === undefined || state.since_ts === null || Number.isFinite(state.since_ts)))) {
        return null;
      }
      return value as unknown as Extract<RelayServerControlFrame, { type: "presence" }>;
    case "rooms":
      return isNonEmptyString(value.peer) && Array.isArray(value.rooms) && value.rooms.every(isRoom)
        ? value as unknown as Extract<RelayServerControlFrame, { type: "rooms" }>
        : null;
    case "room_announced":
      return isNonEmptyString(value.peer) && isRoom(value)
        ? value as unknown as Extract<RelayServerControlFrame, { type: "room_announced" }>
        : null;
    case "room_ended":
      return isNonEmptyString(value.peer) && isNonEmptyString(value.room_id) && Number.isFinite(value.since_ts)
        ? value as unknown as Extract<RelayServerControlFrame, { type: "room_ended" }>
        : null;
    default:
      return null;
  }
}

function isEnvelope(value: unknown): boolean {
  if (!isRecord(value)) return false;
  const to = value.to;
  return isNonEmptyString(value.from) &&
    (isNonEmptyString(to) || (Array.isArray(to) && to.every(isNonEmptyString))) &&
    isNonEmptyString(value.id) &&
    (value.re === null || typeof value.re === "string") &&
    Object.hasOwn(value, "body");
}

function parseCrossPc(value: Record<string, unknown>): CrossPcFramePiEnvelopeIn | null {
  return value.type === "pi_envelope_in" &&
    isNonEmptyString(value.from_pc) &&
    isNonEmptyString(value.to_room) &&
    isEnvelope(value.envelope)
    ? value as unknown as CrossPcFramePiEnvelopeIn
    : null;
}

function parseOuter(value: Record<string, unknown>): RelayOuterEnvelope | null {
  if (!isNonEmptyString(value.peer) || !isNonEmptyString(value.ct)) return null;
  if (value.room !== undefined && typeof value.room !== "string") return null;
  return {
    peer: value.peer,
    ct: value.ct,
    ...(typeof value.room === "string" ? { room: value.room } : {}),
  };
}

function decodeBase64Bounded(value: string, maxDecodedBytes: number): Buffer {
  const maxEncodedBytes = 4 * Math.ceil(maxDecodedBytes / 3);
  if (Buffer.byteLength(value, "ascii") > maxEncodedBytes) {
    throw new RelayIngressDecodeError("too_large", value.length);
  }
  if (value.length % 4 === 1 || !/^[A-Za-z0-9+/_-]*={0,2}$/.test(value)) {
    throw new RelayIngressDecodeError("invalid_message", value.length);
  }

  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - normalized.length % 4) % 4);
  const decoded = Buffer.from(padded, "base64");
  if (decoded.byteLength > maxDecodedBytes) {
    throw new RelayIngressDecodeError("too_large", decoded.byteLength);
  }
  return decoded;
}

/** Decode one post-auth relay line exactly once into generated control/cross-PC DTOs or a typed outer envelope. */
export function decodeRelayIngress(
  line: string,
  limits: Partial<RelayIngressLimits> = {},
): DecodedRelayIngress {
  const effective = { ...DEFAULT_LIMITS, ...limits };
  const rawBytes = Buffer.byteLength(line, "utf8");
  if (rawBytes > effective.maxRawBytes) {
    throw new RelayIngressDecodeError("too_large", rawBytes);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(line) as unknown;
  } catch {
    throw new RelayIngressDecodeError("invalid_message", rawBytes);
  }
  if (!isRecord(parsed)) {
    throw new RelayIngressDecodeError("invalid_message", rawBytes);
  }

  if (typeof parsed.type === "string") {
    const crossPc = parseCrossPc(parsed);
    if (crossPc) return { kind: "cross_pc", frame: crossPc };
    const control = parseServerControl(parsed);
    if (control) return { kind: "control", frame: control };
    throw new RelayIngressDecodeError("unsupported_type", rawBytes);
  }

  const outer = parseOuter(parsed);
  if (!outer) throw new RelayIngressDecodeError("invalid_message", rawBytes);
  const payload = decodeBase64Bounded(outer.ct, effective.maxDecodedPayloadBytes);
  return { kind: "outer", frame: outer, payloadUtf8: payload.toString("utf8") };
}

/** Decode and validate one bounded relay auth challenge without echoing its contents. */
export function decodeRelayChallenge(line: string): RelayControlFrameChallenge {
  const rawBytes = Buffer.byteLength(line, "utf8");
  if (rawBytes > RELAY_MAX_PRE_AUTH_FRAME_BYTES) {
    throw new RelayIngressDecodeError("too_large", rawBytes);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(line) as unknown;
  } catch {
    throw new RelayIngressDecodeError("invalid_message", rawBytes);
  }
  if (!isRecord(parsed) || parsed.type !== "challenge" || !isNonEmptyString(parsed.nonce)) {
    throw new RelayIngressDecodeError("invalid_message", rawBytes);
  }
  const nonce = decodeBase64Bounded(parsed.nonce, 32);
  if (nonce.byteLength !== 32) {
    throw new RelayIngressDecodeError("invalid_message", nonce.byteLength);
  }
  return { type: "challenge", nonce: parsed.nonce };
}

/** Decode an already-bounded outer payload through the generated ClientMessage validator. */
export function decodeRelayClientPayload(payloadUtf8: string): ClientMessage | null {
  try {
    return decodeClient(payloadUtf8);
  } catch {
    return null;
  }
}

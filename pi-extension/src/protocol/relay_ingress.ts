import { decodeClient } from "./codec.js";
import type { ClientMessage } from "./types.js";
import {
  RELAY_DEFAULT_MAX_DECODED_BYTES,
  RELAY_MAX_PRE_AUTH_FRAME_BYTES,
  RELAY_MAX_RAW_MESSAGE_BYTES,
  isCrossPcFrame,
  isRelayOuterEnvelopeCompat,
  isRelayPostAuthControlFrame,
  isRelayServerControlFrame,
  type CrossPcFramePiEnvelopeIn,
  type RelayControlFrameChallenge,
  type RelayOuterEnvelopeCompat,
  type RelayPostAuthControlFrame,
} from "./generated/protocol.generated.js";

export {
  RELAY_DEFAULT_MAX_DECODED_BYTES,
  RELAY_MAX_FRAME_OVERHEAD_BYTES,
  RELAY_MAX_PRE_AUTH_FRAME_BYTES,
  RELAY_MAX_RAW_MESSAGE_BYTES,
} from "./generated/protocol.generated.js";

/** Relay-to-endpoint control variants consumed after authentication. */
export type RelayServerControlFrame = RelayPostAuthControlFrame;

/** Limits applied before JSON and base64 allocation at relay ingress. */
export interface RelayIngressLimits {
  readonly maxRawBytes: number;
  readonly maxDecodedPayloadBytes: number;
}

/** One typed relay frame after boundary validation and, for outer envelopes, payload decoding. */
export type DecodedRelayIngress =
  | {
      readonly kind: "outer";
      readonly frame: RelayOuterEnvelopeCompat;
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
    if (isCrossPcFrame(parsed) && parsed.type === "pi_envelope_in") {
      return { kind: "cross_pc", frame: parsed };
    }
    if (isRelayPostAuthControlFrame(parsed)) {
      return { kind: "control", frame: parsed };
    }
    throw new RelayIngressDecodeError("unsupported_type", rawBytes);
  }

  if (!isRelayOuterEnvelopeCompat(parsed)) {
    throw new RelayIngressDecodeError("invalid_message", rawBytes);
  }
  const outer = parsed;
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
  if (!isRelayServerControlFrame(parsed) || parsed.type !== "challenge") {
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

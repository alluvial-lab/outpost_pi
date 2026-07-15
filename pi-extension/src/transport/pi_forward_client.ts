import { EventEmitter } from "node:events";
import type { RelayClient } from "./relay_client.js";
import type { Envelope } from "../session/envelope.js";
import type {
  CrossPcFramePiEnvelope,
  CrossPcFramePiEnvelopeIn,
  RelayControlFrameRoomAnnounced,
  RelayControlFrameRoomEnded,
  RelayControlFrameRooms,
  RelayControlFrameRoomsCheck,
  RelayControlFrameSubscribeRooms,
} from "../protocol/generated/protocol.generated.js";
import { crossPcTypes } from "../protocol/generated/protocol.generated.js";

/** Discriminator values derived from the generated `crossPcTypes` registry —
 *  the single source of truth for cross-PC frame type strings. */
const PI_ENVELOPE_TYPE = crossPcTypes[0];  // "pi_envelope"
const PI_ENVELOPE_IN_TYPE = crossPcTypes[1];  // "pi_envelope_in"

/**
 * Plan/25 Wave A wire types — must stay bit-compatible with the relay's
 * `handlers/pi_forward.rs`.
 *
 * Outbound (Pi → relay):
 *   { type: "pi_envelope", to_pc: <pi-b-pubkey-base64>, to_room: <room>, envelope: {...} }
 *
 * Inbound (relay → Pi):
 *   { type: "pi_envelope_in", from_pc: <pi-a-pubkey-base64>, to_room: <room>, envelope: {...} }
 *
 * Transport errors arrive as a regular envelope nested inside the inbound
 * frame, with `envelope.from = "_relay"` and
 * `envelope.body = { type: "transport_error", reason }`. They are NOT a
 * separate frame type — `pi_forward_client` simply emits them through the
 * same `envelope` event and lets `broker_remote` recognize them.
 *
 * The cross-PC frame DTOs are the generated `CrossPcFrame*` types
 * (`protocol.generated.ts`) — the single source of truth for the wire shape.
 * No handwritten mirror is maintained here.
 */

/** Outbound API + inbound listener for Pi↔Pi envelope forwarding via relay. */
export interface PiForwardClientEvents {
  /**
   * Emitted whenever the relay delivers a `pi_envelope_in` frame addressed
   * to this Pi. `fromPc` is the verified Pi-pubkey of the sender (relay
   * authoritative — defense against spoofed `envelope.from`), while `toRoom`
   * is the relay-validated room echoed by the inbound frame.
   */
  envelope: [env: Envelope, fromPc: string, toRoom: string];
  /** Authoritative one-shot room snapshot returned by `rooms_check`. */
  rooms: [frame: RelayControlFrameRooms];
  /** Authoritative push announcing a newly-live sibling room. */
  room_announced: [frame: RelayControlFrameRoomAnnounced];
  /** Authoritative push removing a sibling room from the live set. */
  room_ended: [frame: RelayControlFrameRoomEnded];
}

/** Multiplex opaque cross-PC envelopes over a caller-owned relay and detach its listener during bridge shutdown. */
export class PiForwardClient extends EventEmitter<PiForwardClientEvents> {
  private readonly onRelayMessage: (line: string) => void;
  private detached = false;

  constructor(private readonly relay: RelayClient) {
    super();
    this.onRelayMessage = (line) => this._handleLine(line);
    this.relay.on("message", this.onRelayMessage);
  }

  /**
   * Pack `env` in a `pi_envelope` frame addressed to `toPc` / `toRoom` and send via
   * the relay WS. Best-effort: if the relay is not connected, the call is
   * silently dropped. The caller (broker_remote) handles the timeout via
   * its outstanding-ACK map — a missing ACK from the destination wrapper
   * surfaces as `status: "timeout"` upstream regardless.
   *
   * `toRoom` targets a specific room of the destination peer (room-targeted
   * delivery, not peer-wide fanout); the relay routes only to that room.
   */
  sendEnvelopeToPi(toPc: string, toRoom: string, env: Envelope): void {
    if (this.detached) return;
    const frame: CrossPcFramePiEnvelope = {
      type: PI_ENVELOPE_TYPE,
      to_pc: toPc,
      to_room: toRoom,
      envelope: env,
    };
    try {
      this.relay.send(JSON.stringify(frame));
    } catch {
      // relay not connected; broker_remote's pending logic will time out
    }
  }

  /** Send a relay-authoritative room subscription or snapshot request. */
  sendRoomControl(frame: RelayControlFrameSubscribeRooms | RelayControlFrameRoomsCheck): void {
    if (this.detached) return;
    this.relay.sendControl(frame);
  }

  /** Stop listening to the relay. Call from `_goIdle` / shutdown. */
  detach(): void {
    if (this.detached) return;
    this.detached = true;
    this.relay.off("message", this.onRelayMessage);
  }

  private _handleLine(line: string): void {
    if (this.detached) return;
    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch {
      return;
    }
    if (!isRecord(parsed) || typeof parsed.type !== "string") return;

    if (parsed.type === PI_ENVELOPE_IN_TYPE) {
      const o = parsed as Partial<CrossPcFramePiEnvelopeIn>;
      if (
        typeof o.from_pc !== "string" ||
        typeof o.to_room !== "string" ||
        o.to_room.length === 0 ||
        !o.envelope ||
        typeof o.envelope !== "object"
      ) return;

      // Cheap shape check — full envelope parse happens downstream in broker_remote.
      const env = o.envelope as Envelope;
      if (typeof env.from !== "string" || typeof env.id !== "string") return;
      if (this.detached) return;
      this.emit("envelope", env, o.from_pc, o.to_room);
      return;
    }

    if (parsed.type === "rooms") {
      const frame = parseRoomsFrame(parsed);
      if (frame && !this.detached) this.emit("rooms", frame);
      return;
    }

    if (parsed.type === "room_announced") {
      const frame = parseRoomAnnouncedFrame(parsed);
      if (frame && !this.detached) this.emit("room_announced", frame);
      return;
    }

    if (parsed.type === "room_ended") {
      const frame = parseRoomEndedFrame(parsed);
      if (frame && !this.detached) this.emit("room_ended", frame);
    }
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function hasRoomIdentity(value: unknown): value is Record<string, unknown> & {
  room_id: string;
  started_at: number;
} {
  return isRecord(value) &&
    typeof value.room_id === "string" &&
    value.room_id.length > 0 &&
    Number.isInteger(value.started_at) &&
    (value.started_at as number) >= 0;
}

function hasOptionalString(value: Record<string, unknown>, key: string): boolean {
  return value[key] === undefined || typeof value[key] === "string";
}

function isLiveRoom(value: unknown): boolean {
  if (!hasRoomIdentity(value) || typeof value.working !== "boolean") return false;
  return ["name", "cwd", "session_id", "model", "thinking"]
    .every((key) => hasOptionalString(value, key));
}

function parseRoomsFrame(value: Record<string, unknown>): RelayControlFrameRooms | null {
  if (typeof value.peer !== "string" || value.peer.length === 0 || !Array.isArray(value.rooms)) {
    return null;
  }
  if (!value.rooms.every(isLiveRoom)) return null;
  return value as unknown as RelayControlFrameRooms;
}

function parseRoomAnnouncedFrame(
  value: Record<string, unknown>,
): RelayControlFrameRoomAnnounced | null {
  if (
    typeof value.peer !== "string" ||
    value.peer.length === 0 ||
    !isLiveRoom(value)
  ) return null;
  return value as unknown as RelayControlFrameRoomAnnounced;
}

function parseRoomEndedFrame(value: Record<string, unknown>): RelayControlFrameRoomEnded | null {
  if (
    typeof value.peer !== "string" ||
    value.peer.length === 0 ||
    typeof value.room_id !== "string" ||
    value.room_id.length === 0 ||
    !Number.isInteger(value.since_ts) ||
    (value.since_ts as number) < 0
  ) return null;
  return value as unknown as RelayControlFrameRoomEnded;
}

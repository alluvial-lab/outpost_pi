import {
  decodeRelayClientPayload,
  decodeRelayIngress,
} from "../protocol/relay_ingress.js";
import type { ClientMessage, ServerMessage } from "../protocol/types.js";
import type { RelayClient } from "./relay_client.js";

/** Sink for ServerMessage outbound to the remote app. */
export interface PeerChannel {
  send(msg: ServerMessage): void;
}

/**
 * Canonical room a mobile app authenticates in. The app's `hello.room_id` is
 * hardcoded to `"main"` (`app/lib/data/transport/ws_transport.dart`), so every
 * app peer registers at `(appPubkey, "main")` in the relay's connection
 * registry. The Pi must address outbound envelopes to this room so the relay's
 * `dispatch_outer` (`send_to_room(&dest_peer, &dest_room, …)`) finds the app.
 *
 * The relay then rewrites the DELIVERED envelope's `room` to the SENDER's auth
 * room (this Pi's cwd-room) for anti-spoof; the app's inbound filter expects
 * that (its `activeRoom` is set to the Pi's room after pairing).
 */
const APP_DESTINATION_ROOM = "main";

/**
 * Outer envelope shape forwarded by the relay.
 * { "peer": "<dest peer_id>", "room": "<dest room_id>", "ct": "<base64 JSON inner>" }
 *
 * Post rollback (plan 06): `ct` is base64(JSON.stringify(inner)) — no cipher,
 * no MAC. Relay continues opaque (never JSON.parses ct).
 *
 * `room` (relay-0.2.0 paired wire change): REQUIRED on every outbound frame —
 * `relay/src/protocol/generated/outer.rs` derives `pub room: String` (non-optional,
 * `deny_unknown_fields`), so a frame missing `room` is rejected with
 * `invalid json: missing field room` and dropped. It is the DESTINATION room
 * (where the app registered) used for `(peer, room)` routing, NOT the sender's
 * room (the relay overwrites the delivered frame's `room` with the sender's auth
 * room for anti-spoof).
 */
interface OuterEnvelope {
  peer: string;
  room: string;
  ct: string;
}

/**
 * Plaintext PeerChannel backed by a RelayClient WebSocket.
 *
 * Usage (after pair_request handshake completes):
 *   const channel = new PlainPeerChannel(relay, appPeerId, onMsg)
 *   channel.send(serverMessage)          // base64-encodes JSON, routes via relay
 *   // incoming relay messages destined for appPeerId are auto-decoded
 *   // and delivered via onMessage callback
 */
export class PlainPeerChannel implements PeerChannel {
  private readonly _unsubscribe: () => void;
  private detached = false;

  constructor(
    private readonly relay: RelayClient,
    private readonly remotePeerId: string,
    private readonly onMessage: (msg: ClientMessage) => void,
    /** Called when this specific peer connection is considered lost. */
    _onDisconnect?: () => void,
  ) {
    const listener = (line: string) => this._onLine(line);
    relay.on("message", listener);
    this._unsubscribe = () => relay.off("message", listener);
    void _onDisconnect;
  }

  // ── PeerChannel interface ──────────────────────────────────────────────────

  send(msg: ServerMessage): void {
    if (this.detached) return;
    const ct = Buffer.from(JSON.stringify(msg)).toString("base64");
    // `room` is the DESTINATION room (the app's auth room, "main") so the
    // relay routes to the app's `(peer, "main")` connection. relay-0.2.0
    // requires this field (rejects `{peer, ct}` with `missing field room`).
    const outer: OuterEnvelope = { peer: this.remotePeerId, room: APP_DESTINATION_ROOM, ct };
    // Best-effort delivery. The relay WS can be mid-reconnect (idle/NAT drop, or
    // a session_new/session-replacement teardown) when we push a server→app frame
    // — notably the action_ok/action_error ack a handler emits right after
    // newSession. `relay.send` throws "relay: not connected" in that window; since
    // this runs inside an async SDK event callback, letting it propagate becomes an
    // uncaughtException that kills the whole pi process. The relay auto-reconnects
    // and the app re-syncs via session_sync, so a dropped frame is recoverable — a
    // crash is not. Mirrors RelayClient.sendControl's no-op-when-closed policy.
    try {
      this.relay.send(JSON.stringify(outer));
    } catch {
      /* relay down — drop this frame; reconnect + session_sync will recover */
    }
  }

  /** Detaches from relay (does not close the relay itself). */
  detach(): void {
    if (this.detached) return;
    this.detached = true;
    this._unsubscribe();
  }

  // ── Incoming line from relay ────────────────────────────────────────────────

  private _onLine(line: string): void {
    if (this.detached) return;
    let decoded;
    try {
      decoded = decodeRelayIngress(line);
    } catch {
      return;
    }
    if (decoded.kind !== "outer" || decoded.frame.peer !== this.remotePeerId) return;

    const msg = decodeRelayClientPayload(decoded.payloadUtf8);
    if (!msg || this.detached) return;
    this.onMessage(msg);
  }
}

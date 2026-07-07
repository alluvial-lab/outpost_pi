import { appendFileSync } from "node:fs";
import { decodeClient } from "../protocol/codec.js";
import type { ClientMessage, ServerMessage } from "../protocol/types.js";
import type { RelayClient } from "./relay_client.js";

// TEMP DEBUG (subagent-leak third-path hunt): log EVERY ServerMessage frame
// that leaves for the phone, with the subagent-gate state + a content preview.
// PeerChannel.send is the true sink — both `OwnerMultiplexer.broadcast` and
// direct `sender.send` (e.g. session_sync/session_history replies) funnel here —
// so this single instrumentation captures all outbound paths. Env-gated
// (REMOTE_PI_DEBUG_SEND=1) so it is inert in normal runs. Remove after the leak
// path is found and gated. See
// story-extension-suppress-subagent-assistant-broadcast.
const _DEBUG_SEND = process.env.REMOTE_PI_DEBUG_SEND === "1";
const _DEBUG_SEND_LOG = process.env.REMOTE_PI_DEBUG_SEND_LOG ?? "/tmp/remote-pi-debug-send.jsonl";
let _subagentGateActive: () => boolean = () => false;
/** TEMP DEBUG: lets index.ts register the live gate-state reader for logging. */
export function _debugSetSubagentGateReader(reader: () => boolean): void {
  _subagentGateActive = reader;
}
function _debugPreview(msg: ServerMessage): string | null {
  const m = msg as { delta?: string; text?: string; message?: string; events?: unknown[] };
  if (typeof m.delta === "string" && m.delta) return m.delta.slice(0, 80);
  if (typeof m.text === "string" && m.text) return m.text.slice(0, 80);
  if (typeof m.message === "string" && m.message) return m.message.slice(0, 80);
  if (Array.isArray(m.events)) return `events[${m.events.length}]`;
  return null;
}

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
 * Post rollback (plano 06): `ct` is base64(JSON.stringify(inner)) — no cipher,
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
    // TEMP DEBUG (subagent-leak third-path hunt): log every outbound frame
    // with type + gate state + preview. Env-gated so inert unless enabled.
    if (_DEBUG_SEND) {
      try {
        appendFileSync(_DEBUG_SEND_LOG, JSON.stringify({
          ts: Date.now(),
          sink: "peer",
          peer: this.remotePeerId,
          type: (msg as { type?: string }).type ?? "<unknown>",
          sessionId: (msg as { session_id?: string }).session_id ?? null,
          gateActive: _subagentGateActive(),
          replyTo: (msg as { in_reply_to?: string }).in_reply_to ?? null,
          preview: _debugPreview(msg),
        }) + "\n");
      } catch { /* best-effort */ }
    }
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
    let outer: OuterEnvelope;
    try {
      outer = JSON.parse(line) as OuterEnvelope;
    } catch {
      return; // malformed line
    }

    if (outer.peer !== this.remotePeerId) return;
    if (!outer.ct) return;

    let plaintext: string;
    try {
      plaintext = Buffer.from(outer.ct, "base64").toString("utf8");
    } catch {
      return;
    }

    let msg: ClientMessage;
    try {
      msg = decodeClient(plaintext);
    } catch {
      return;
    }

    if (this.detached) return;
    this.onMessage(msg);
  }
}

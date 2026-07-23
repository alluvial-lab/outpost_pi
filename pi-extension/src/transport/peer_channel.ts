import { appendFile, chmod, mkdir } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import {
  decodeRelayClientPayload,
  type DecodedRelayIngress,
} from "../protocol/relay_ingress.js";
import type { RelayOuterEnvelope } from "../protocol/generated/protocol.generated.js";
import type { ClientMessage, ServerMessage } from "../protocol/types.js";
import type { RelayClient } from "./relay_client.js";
import { subscribeRelayIngress } from "./relay_ingress_fanout.js";
import { open, seal, type DirectionalKeys } from "./secure_channel.js";

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
 * Plaintext PeerChannel backed by a RelayClient WebSocket.
 *
 * This adapter is restricted to the pre-key pair_request/pair_ok exchange.
 * Established owners must use {@link SecurePeerChannel}; there is no
 * post-pairing plaintext fallback.
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
    this._unsubscribe = subscribeRelayIngress(relay, (ingress) => this._onIngress(ingress));
    void _onDisconnect;
  }

  // ── PeerChannel interface ──────────────────────────────────────────────────

  send(msg: ServerMessage): void {
    if (this.detached) return;
    const ct = Buffer.from(JSON.stringify(msg)).toString("base64");
    // `room` is the DESTINATION room (the app's auth room, "main") so the
    // relay routes to the app's `(peer, "main")` connection. relay-0.2.0
    // requires this field (rejects `{peer, ct}` with `missing field room`).
    const outer: RelayOuterEnvelope = {
      peer: this.remotePeerId,
      room: APP_DESTINATION_ROOM,
      ct,
    };
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

  // ── Typed ingress from the relay transport ─────────────────────────────────

  private _onIngress(decoded: DecodedRelayIngress): void {
    if (this.detached) return;
    if (decoded.kind !== "outer" || decoded.frame.peer !== this.remotePeerId) return;

    const msg = decodeRelayClientPayload(decoded.payloadUtf8);
    if (!msg || this.detached) return;
    this.onMessage(msg);
  }
}

/** State and boundary effects required by one persisted secure owner channel. */
export interface SecurePeerChannelOptions {
  keys: DirectionalKeys;
  sendSeq: bigint;
  recvSeq: bigint;
  persistSequences(patch: { sendSeq?: bigint; recvSeq?: bigint }): Promise<boolean>;
  onDisconnect(): void;
  auditPath?: string;
}

interface OwnerChannelAuditEvent {
  reason: "plaintext_post_key" | "open_failed" | "sequence_persist_failed" | "sequence_exhausted";
  seq?: bigint;
  consecutiveFailures?: number;
}

const DEFAULT_OWNER_CHANNEL_AUDIT_PATH = join(homedir(), ".pi", "remote", "owner-channel-audit.jsonl");
const MAX_OPEN_FAILURES = 5;

/** Append one content-free owner-channel security decision to the private audit log. */
export async function appendOwnerChannelAudit(
  peerId: string,
  reason: "missing_channel_key",
  auditPath = DEFAULT_OWNER_CHANNEL_AUDIT_PATH,
): Promise<void> {
  const line = `${JSON.stringify({ ts: Date.now(), peer: peerId, reason })}\n`;
  try {
    await mkdir(dirname(auditPath), { recursive: true, mode: 0o700 });
    await appendFile(auditPath, line, { encoding: "utf8", mode: 0o600 });
    try { await chmod(auditPath, 0o600); } catch { /* unsupported permissions */ }
  } catch {
    // Best-effort audit cannot turn a fail-closed drop into an availability failure.
  }
}

/**
 * Relay-backed protected owner channel with persisted replay high-waters.
 *
 * Outbound work is serialized and persists each new send high-water before the
 * corresponding frame is exposed to the relay. Inbound plaintext, AEAD failures,
 * and replay are dropped without reaching the message router. Five consecutive
 * protected-frame failures detach this adapter; the next protected frame can
 * automatically reattach from the same persisted key, while AEAD remains the
 * authorization boundary.
 */
export class SecurePeerChannel implements PeerChannel {
  private readonly unsubscribe: () => void;
  private readonly auditPath: string;
  private detached = false;
  private disconnectNotified = false;
  private sendSeq: bigint;
  private recvSeq: bigint;
  private consecutiveOpenFailures = 0;
  private outboundTail: Promise<void> = Promise.resolve();
  private inboundTail: Promise<void> = Promise.resolve();
  private auditTail: Promise<void> = Promise.resolve();

  constructor(
    private readonly relay: RelayClient,
    private readonly remotePeerId: string,
    private readonly onMessage: (msg: ClientMessage) => void,
    private readonly options: SecurePeerChannelOptions,
  ) {
    this.sendSeq = options.sendSeq;
    this.recvSeq = options.recvSeq;
    this.auditPath = options.auditPath ?? DEFAULT_OWNER_CHANNEL_AUDIT_PATH;
    this.unsubscribe = subscribeRelayIngress(relay, (ingress) => this.onIngress(ingress));
  }

  send(msg: ServerMessage): void {
    if (this.detached) return;
    let json: string;
    try {
      json = JSON.stringify(msg);
    } catch {
      return;
    }

    this.outboundTail = this.outboundTail.then(async () => {
      // Work accepted before detach remains eligible to finish (notably the
      // best-effort bye queued immediately before listener teardown). Calls
      // made after detach are rejected at the send() boundary above.
      const nextSeq = this.sendSeq + 1n;
      let frame: Uint8Array;
      try {
        frame = seal(this.options.keys.send, nextSeq, json);
      } catch {
        this.audit({ reason: "sequence_exhausted", seq: nextSeq });
        this.disconnect();
        return;
      }
      this.sendSeq = nextSeq;

      try {
        const persisted = await this.options.persistSequences({ sendSeq: nextSeq });
        if (!persisted) {
          this.audit({ reason: "sequence_persist_failed", seq: nextSeq });
          if (!this.detached) this.disconnect();
          return;
        }
      } catch {
        this.audit({ reason: "sequence_persist_failed", seq: nextSeq });
        if (!this.detached) this.disconnect();
        return;
      }

      const outer: RelayOuterEnvelope = {
        peer: this.remotePeerId,
        room: APP_DESTINATION_ROOM,
        ct: Buffer.from(frame).toString("base64"),
      };
      try {
        this.relay.send(JSON.stringify(outer));
      } catch {
        // The authenticated seq header permits a safe gap after reconnect;
        // session_sync recovers the dropped application frame.
      }
    });
  }

  /** Detach the channel's relay subscription without closing the shared relay. */
  detach(): void {
    if (this.detached) return;
    this.detached = true;
    this.unsubscribe();
  }

  /** Test/teardown seam: wait until queued persistence, ingress, and audit work settles. */
  async whenIdle(): Promise<void> {
    await this.outboundTail;
    await this.inboundTail;
    await this.auditTail;
  }

  private onIngress(decoded: DecodedRelayIngress): void {
    if (this.detached || decoded.kind !== "outer" || decoded.frame.peer !== this.remotePeerId) return;
    const frame = Buffer.from(decoded.frame.ct, "base64");
    if (frame[0] !== 0x01) {
      this.audit({ reason: "plaintext_post_key" });
      return;
    }
    this.inboundTail = this.inboundTail.then(() => this.openAndRoute(frame));
  }

  private async openAndRoute(frame: Uint8Array): Promise<void> {
    if (this.detached) return;
    const opened = open(this.options.keys.recv, frame, this.recvSeq);
    if (!opened) {
      this.consecutiveOpenFailures += 1;
      this.audit({
        reason: "open_failed",
        seq: frame.length >= 9
          ? new DataView(frame.buffer, frame.byteOffset + 1, 8).getBigUint64(0, true)
          : undefined,
        consecutiveFailures: this.consecutiveOpenFailures,
      });
      if (this.consecutiveOpenFailures >= MAX_OPEN_FAILURES) this.disconnect();
      return;
    }

    let message: ClientMessage | null = null;
    try {
      message = decodeRelayClientPayload(opened.json);
    } catch {
      message = null;
    }
    if (!message) {
      this.consecutiveOpenFailures += 1;
      this.audit({ reason: "open_failed", seq: opened.seq, consecutiveFailures: this.consecutiveOpenFailures });
      if (this.consecutiveOpenFailures >= MAX_OPEN_FAILURES) this.disconnect();
      return;
    }

    try {
      const persisted = await this.options.persistSequences({ recvSeq: opened.seq });
      if (this.detached) return;
      if (!persisted) {
        this.audit({ reason: "sequence_persist_failed", seq: opened.seq });
        this.disconnect();
        return;
      }
    } catch {
      if (this.detached) return;
      this.audit({ reason: "sequence_persist_failed", seq: opened.seq });
      this.disconnect();
      return;
    }

    this.recvSeq = opened.seq;
    this.consecutiveOpenFailures = 0;
    this.onMessage(message);
  }

  private disconnect(): void {
    if (this.disconnectNotified) return;
    this.disconnectNotified = true;
    this.detach();
    this.options.onDisconnect();
  }

  private audit(event: OwnerChannelAuditEvent): void {
    const line = `${JSON.stringify({
      ts: Date.now(),
      peer: this.remotePeerId,
      reason: event.reason,
      ...(event.seq === undefined ? {} : { seq: event.seq.toString(10) }),
      ...(event.consecutiveFailures === undefined ? {} : { count: event.consecutiveFailures }),
    })}\n`;
    this.auditTail = this.auditTail.then(async () => {
      try {
        await mkdir(dirname(this.auditPath), { recursive: true, mode: 0o700 });
        await appendFile(this.auditPath, line, { encoding: "utf8", mode: 0o600 });
        try { await chmod(this.auditPath, 0o600); } catch { /* unsupported permissions */ }
      } catch {
        // Best-effort and privacy-safe: audit failure must not expose payloads
        // or reopen a rejected channel.
      }
    });
  }
}

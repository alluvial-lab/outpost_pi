import { EventEmitter } from "node:events";
import WebSocket from "ws";
import { ed25519Sign } from "../pairing/crypto.js";
import type { Ed25519Keypair } from "../pairing/crypto.js";
import {
  RELAY_AUTH_DOMAIN_PREFIX,
  RELAY_CONTROL_DISCRIMINATORS,
  type RelayControlFrameAuth,
  type RelayControlFrameHello,
} from "../protocol/generated/protocol.generated.js";
import {
  decodeRelayChallenge,
  RELAY_MAX_PRE_AUTH_FRAME_BYTES,
  RELAY_MAX_RAW_MESSAGE_BYTES,
} from "../protocol/relay_ingress.js";
import {
  REACHABILITY_RELAY_LIVENESS_CHECK_MS,
  REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS,
} from "../reachability/reachability_contract.js";

const RELAY_AUTH_DOMAIN_PREFIX_BYTES = Buffer.from(RELAY_AUTH_DOMAIN_PREFIX, "utf8");

const AUTH_TIMEOUT_MS = 5_000;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Build the exact bytes covered by a relay-auth signature. */
export function relayAuthSigningBytes(nonce: Uint8Array): Buffer {
  return Buffer.concat([RELAY_AUTH_DOMAIN_PREFIX_BYTES, nonce]);
}

/**
 * Liveness watchdog. The relay sends a WS Ping every ~25s (relay `peer.rs`),
 * so a healthy connection sees inbound frames at least that often. If NOTHING
 * arrives for this long the socket is silently dead — NAT/router idle drop,
 * laptop sleep, or the relay/Cloudflare reaping the connection WITHOUT a clean
 * close frame. That half-open case never fires `close`, so reconnect never
 * triggers and a background daemon sits "online" but dead after a few idle
 * hours. We force-close on timeout so `close` drives the caller's reconnect.
 */
const LIVENESS_TIMEOUT_MS = REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS;  // ~2.8 missed relay pings → confidently dead
const LIVENESS_CHECK_MS = REACHABILITY_RELAY_LIVENESS_CHECK_MS;

export interface RoomMeta {
  name: string;
  cwd: string;
  /** Opaque Pi SDK session discriminator. Carried by relay metadata for app bootstrap; relay must not route or log by it. */
  session_id?: string;
  /** Friendly model name (e.g. "claude-sonnet-4.5"). Optional — pi-ext sends
   *  when `ExtensionContext.model` is available; relay/app tolerate absence. */
  model?: string;
  thinking?: string;
  working?: boolean;
  /** True while background subagents (pi-subagents tasks) are queued/running beyond the agent turn. Optional — older apps ignore it. */
  background?: boolean;
}

export interface ConnectOptions {
  roomId?: string;
  roomMeta?: RoomMeta;
}

/** Relay rejected hello because another peer already holds (pubkey, room_id). */
export class RoomAlreadyOpenError extends Error {
  constructor(public readonly roomId: string | undefined) {
    super(
      roomId
        ? `relay rejected hello: room ${roomId} already open for this peer`
        : "relay rejected hello: peer already connected",
    );
    this.name = "RoomAlreadyOpenError";
  }
}

export interface RelayClientEvents {
  /** A single JSONL line delivered by the relay (outer envelope). */
  message: [line: string];
  close: [];
  error: [err: Error];
}

/**
 * Thin WebSocket client for the Outpost-Pi relay.
 *
 * Lifecycle:
 *   const relay = new RelayClient(url, ed25519Keypair)
 *   await relay.connect()          // opens WS + runs Ed25519 challenge-response
 *   relay.on("message", line => …) // outer envelopes: { peer, ct }
 *   relay.send(jsonLine)           // write to relay
 *   relay.close()
 *
 * Auth sequence (pairing.md §Challenge-response):
 *   → { type:"hello",     pubkey: "<Ed25519 pubkey base64>" }
 *   ← { type:"challenge", nonce:  "<32 bytes base64>" }
 *   → { type:"auth",      sig:    "<Ed25519 sig base64>" }
 */
export class RelayClient extends EventEmitter {
  private ws: WebSocket | null = null;
  /** Epoch ms of the last inbound frame (message / relay ping / pong). */
  private lastActivityAt = 0;
  private livenessTimer: ReturnType<typeof setInterval> | null = null;

  constructor(
    private readonly url: string,
    private readonly keypair: Ed25519Keypair,
    private readonly deviceId: string,
  ) {
    super();
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /**
   * Connects and completes Ed25519 auth.  Resolves when relay is ready.
   *
   * `options.roomId` (12-char id derived from cwd, see `src/rooms.ts`) is
   * included in the hello so the relay can multiplex N concurrent peers
   * with the same Ed25519 pubkey but different rooms (one pi-ext per cwd).
   * Omitting `roomId` is backward-compat with old relays (treated as the
   * default "main" room server-side).
   *
   * Throws `RoomAlreadyOpenError` if the relay rejects the hello because
   * another peer already holds the (pubkey, room_id) tuple. Caller (e.g.
   * `_cmdStart`) maps that to a clearer UI message.
   */
  async connect(options: ConnectOptions = {}): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const ws = new WebSocket(this.url, { maxPayload: RELAY_MAX_RAW_MESSAGE_BYTES });
      this.ws = ws;

      ws.on("error", (err) => reject(err));

      ws.on("open", async () => {
        try {
          await this._authenticate(ws, options);

          // Auth done — wire persistent message handler. Every inbound frame
          // (data, plus the relay's keepalive ping/pong below) refreshes the
          // liveness clock.
          this.lastActivityAt = Date.now();
          ws.on("message", (raw) => {
            this.lastActivityAt = Date.now();
            const text = Buffer.isBuffer(raw) ? raw.toString() : String(raw);
            for (const line of text.split("\n")) {
              const trimmed = line.trim();
              if (trimmed) this.emit("message", trimmed);
            }
          });
          // The relay pings every ~25s; `ws` auto-replies Pong (keeping the
          // relay's view of us alive). The relay ignores client pings rather
          // than ponging, so these inbound pings — not a ping/pong we initiate
          // — are our liveness signal.
          ws.on("ping", () => { this.lastActivityAt = Date.now(); });
          ws.on("pong", () => { this.lastActivityAt = Date.now(); });

          ws.on("close", () => {
            this._stopLiveness();
            this.emit("close");
          });
          this._startLiveness(ws);
          resolve();
        } catch (err) {
          ws.terminate();
          reject(err);
        }
      });
    });
  }

  /** Sends a raw line to the relay (caller is responsible for framing). */
  send(line: string): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      throw new Error("relay: not connected");
    }
    this.ws.send(line);
  }

  /**
   * Sends a control frame to the relay (not routed to app peer). Used for
   * out-of-band metadata updates like `room_meta_update`. Silently no-ops if
   * the WS isn't open (best-effort: control frames are observational; we
   * don't want them throwing inside SDK event callbacks).
   */
  sendControl(frame: object): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    this.ws.send(JSON.stringify(frame));
  }

  close(): void {
    this._stopLiveness();
    this.ws?.close();
    this.ws = null;
  }

  // ── Liveness watchdog ─────────────────────────────────────────────────────

  /** Force-close the WS when no inbound frame has arrived for
   *  `LIVENESS_TIMEOUT_MS` — see the constant's doc for why. `terminate()`
   *  fires `close`, which the owner turns into a reconnect. */
  private _startLiveness(ws: WebSocket): void {
    this._stopLiveness();
    this.livenessTimer = setInterval(() => {
      if (Date.now() - this.lastActivityAt > LIVENESS_TIMEOUT_MS) {
        this._stopLiveness();
        ws.terminate();
      }
    }, LIVENESS_CHECK_MS);
  }

  private _stopLiveness(): void {
    if (this.livenessTimer) {
      clearInterval(this.livenessTimer);
      this.livenessTimer = null;
    }
  }

  // ── Auth ────────────────────────────────────────────────────────────────────

  private async _authenticate(ws: WebSocket, opts: ConnectOptions): Promise<void> {
    const pubkeyB64 = Buffer.from(this.keypair.publicKey).toString("base64");
    const hello = {
      type: RELAY_CONTROL_DISCRIMINATORS.hello,
      pubkey: pubkeyB64,
      device_id: this.deviceId,
      ...(opts.roomId ? { room_id: opts.roomId } : {}),
      ...(opts.roomMeta ? { room_meta: opts.roomMeta } : {}),
    } satisfies RelayControlFrameHello;
    this._rawSend(ws, JSON.stringify(hello));

    const challengeRaw = await this._nextMsg(ws);
    if (Buffer.byteLength(challengeRaw, "utf8") > RELAY_MAX_PRE_AUTH_FRAME_BYTES) {
      throw new Error("relay auth_failed: challenge too large");
    }
    let parsedChallenge: unknown;
    try {
      parsedChallenge = JSON.parse(challengeRaw) as unknown;
    } catch {
      throw new Error("relay auth_failed: malformed challenge");
    }
    if (isRecord(parsedChallenge) && parsedChallenge.type === "error") {
      const code = typeof parsedChallenge.code === "string" ? parsedChallenge.code : "";
      if (code === "room_already_open") {
        throw new RoomAlreadyOpenError(opts.roomId);
      }
      throw new Error("relay rejected hello");
    }

    let challenge;
    try {
      challenge = decodeRelayChallenge(challengeRaw);
    } catch {
      throw new Error("relay auth_failed: invalid challenge");
    }
    const nonce = Buffer.from(challenge.nonce, "base64");
    // Domain-separated auth signature: must match the relay's
    // `RELAY_AUTH_DOMAIN_PREFIX` (relay/src/auth/challenge.rs). The relay
    // verifies the signature over `prefix ++ nonce`, NOT the bare nonce —
    // signing the bare nonce makes the extension a signing oracle for
    // arbitrary Ed25519 messages under the long-term identity key and is
    // rejected by relay-0.2.0 as `invalid signature`.
    const sig = ed25519Sign(this.keypair.secretKey, relayAuthSigningBytes(nonce));
    const auth = {
      type: RELAY_CONTROL_DISCRIMINATORS.auth,
      sig: Buffer.from(sig).toString("base64"),
    } satisfies RelayControlFrameAuth;
    this._rawSend(ws, JSON.stringify(auth));

    // Relay does not send an explicit "ok" — it simply starts routing.
    // Proceed immediately after sending auth.
  }

  /** Waits for the next single WS message with a timeout. */
  private _nextMsg(ws: WebSocket): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      let settled = false;
      const cleanup = (): void => {
        clearTimeout(timer);
        ws.removeListener("message", onMessage);
      };
      const onMessage = (raw: WebSocket.RawData): void => {
        if (settled) return;
        settled = true;
        cleanup();
        resolve(Buffer.isBuffer(raw) ? raw.toString() : String(raw));
      };
      const onTimeout = (): void => {
        if (settled) return;
        settled = true;
        cleanup();
        reject(new Error("relay auth timeout"));
      };
      const timer = setTimeout(onTimeout, AUTH_TIMEOUT_MS);
      ws.once("message", onMessage);
    });
  }

  private _rawSend(ws: WebSocket, data: string): void {
    ws.send(data);
  }
}

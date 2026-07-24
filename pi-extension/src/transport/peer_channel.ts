import { appendFile, chmod, mkdir, rename, stat, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import {
  decodeRelayClientPayload,
  type DecodedRelayIngress,
} from "../protocol/relay_ingress.js";
import type { RelayOuterEnvelope } from "../protocol/generated/protocol.generated.js";
import type { ClientMessage, ServerMessage } from "../protocol/types.js";
import type { RecvSeqAdvanceResult } from "../pairing/storage.js";
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
  recvSeq: bigint;
  reserveSendSeq(): Promise<bigint | null>;
  compareAndAdvanceRecvSeq(recvSeq: bigint): Promise<RecvSeqAdvanceResult>;
  onDisconnect(): void;
  auditPath?: string;
}

type OwnerChannelAuditReason =
  | "missing_channel_key"
  | "plaintext_post_key"
  | "open_failed"
  | "ingress_overflow"
  | "outbound_overflow"
  | "sequence_persist_failed"
  | "stale_generation"
  | "sequence_exhausted";

interface OwnerChannelAuditEvent {
  reason: OwnerChannelAuditReason;
  seq?: bigint;
  consecutiveFailures?: number;
  occurrences?: number;
}

interface OwnerChannelAuditBucket {
  peer: string;
  reason: OwnerChannelAuditReason;
  pendingCount: number;
  lastSeq?: bigint;
  maxConsecutiveFailures?: number;
  emitted: boolean;
  lastEmittedAt: number;
}

const DEFAULT_OWNER_CHANNEL_AUDIT_PATH = join(homedir(), ".pi", "remote", "owner-channel-audit.jsonl");
const MAX_OPEN_FAILURES = 5;
/** Maximum protected inbound frames retained while sequence persistence is pending. */
export const MAX_PENDING_OWNER_FRAMES = 64;
/**
 * Maximum outbound frames retained while send-sequence reservation is pending.
 * 512 comfortably absorbs normal agent_chunk streaming bursts.
 */
export const MAX_PENDING_OWNER_OUTBOUND_FRAMES = 512;
/**
 * Maximum serialized outbound payload retained while reservation is pending.
 * 16 MiB admits several schema-maximum messages while bounding image/replay bursts.
 */
export const MAX_PENDING_OWNER_OUTBOUND_BYTES = 16 * 1024 * 1024;
/** Emit a counted repeat summary after this many suppressed identical decisions. */
export const OWNER_CHANNEL_AUDIT_SUMMARY_EVENTS = 100;
/** Hard cap for the active audit file; one equally bounded rotated predecessor is retained. */
export const OWNER_CHANNEL_AUDIT_MAX_BYTES = 256 * 1024;
const OWNER_CHANNEL_AUDIT_SUMMARY_MS = 5_000;
const OWNER_CHANNEL_AUDIT_MAX_PEER_BUCKETS = 252;
const OWNER_CHANNEL_AUDIT_MAX_PEER_LENGTH = 128;

/**
 * Coalesce owner-channel decisions behind one in-flight file operation.
 *
 * Each peer/reason occupies one fixed-size bucket. Repeated ingress increments
 * counters rather than allocating promises or log lines; a first event flushes
 * immediately and repeats flush at a fixed count/time cadence. The active file
 * rotates before crossing its cap, retaining at most one capped predecessor.
 */
class OwnerChannelAuditor {
  private readonly buckets = new Map<string, OwnerChannelAuditBucket>();
  private writeInFlight: Promise<void> | null = null;
  private flushTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(private readonly auditPath: string) {}

  record(peerId: string, event: OwnerChannelAuditEvent): void {
    const peer = peerId.slice(0, OWNER_CHANNEL_AUDIT_MAX_PEER_LENGTH);
    let key = `${peer}\0${event.reason}`;
    let bucket = this.buckets.get(key);
    if (!bucket) {
      const peerBucketCount = [...this.buckets.keys()].filter((candidate) => !candidate.startsWith("overflow\0")).length;
      if (peerBucketCount >= OWNER_CHANNEL_AUDIT_MAX_PEER_BUCKETS) {
        key = `overflow\0${event.reason}`;
        bucket = this.buckets.get(key);
      }
      if (!bucket) {
        bucket = {
          peer: key.startsWith("overflow\0") ? "overflow" : peer,
          reason: event.reason,
          pendingCount: 0,
          emitted: false,
          lastEmittedAt: 0,
        };
        this.buckets.set(key, bucket);
      }
    }

    bucket.pendingCount += Math.max(1, Math.floor(event.occurrences ?? 1));
    if (event.seq !== undefined) bucket.lastSeq = event.seq;
    if (event.consecutiveFailures !== undefined) {
      bucket.maxConsecutiveFailures = Math.max(
        bucket.maxConsecutiveFailures ?? 0,
        event.consecutiveFailures,
      );
    }

    if (!bucket.emitted || bucket.pendingCount >= OWNER_CHANNEL_AUDIT_SUMMARY_EVENTS) {
      this.requestFlush(false);
    } else {
      this.scheduleFlush();
    }
  }

  async whenIdle(): Promise<void> {
    this.clearFlushTimer();
    while (true) {
      this.requestFlush(true);
      const work = this.writeInFlight;
      if (!work) return;
      await work;
    }
  }

  stats(): { bucketCount: number; activeWrites: number; pendingEvents: number } {
    return {
      bucketCount: this.buckets.size,
      activeWrites: this.writeInFlight ? 1 : 0,
      pendingEvents: [...this.buckets.values()].reduce((total, bucket) => total + bucket.pendingCount, 0),
    };
  }

  private requestFlush(force: boolean): void {
    if (this.writeInFlight) return;
    const now = Date.now();
    const due = [...this.buckets.values()].filter((bucket) =>
      bucket.pendingCount > 0 && (
        force ||
        !bucket.emitted ||
        bucket.pendingCount >= OWNER_CHANNEL_AUDIT_SUMMARY_EVENTS ||
        now - bucket.lastEmittedAt >= OWNER_CHANNEL_AUDIT_SUMMARY_MS
      )
    );
    if (due.length === 0) {
      this.scheduleFlush();
      return;
    }

    this.clearFlushTimer();
    const lines = due.map((bucket) => {
      const count = bucket.pendingCount;
      bucket.pendingCount = 0;
      bucket.emitted = true;
      bucket.lastEmittedAt = now;
      return `${JSON.stringify({
        ts: now,
        peer: bucket.peer,
        reason: bucket.reason,
        count,
        ...(bucket.lastSeq === undefined ? {} : { seq: bucket.lastSeq.toString(10) }),
        ...(bucket.maxConsecutiveFailures === undefined
          ? {}
          : { consecutive_failures: bucket.maxConsecutiveFailures }),
      })}\n`;
    });

    this.writeInFlight = this.appendBounded(lines.join(""))
      .catch(() => {
        // Best-effort audit cannot turn a fail-closed drop into an availability failure.
      })
      .finally(() => {
        this.writeInFlight = null;
        this.requestFlush(false);
      });
  }

  private scheduleFlush(): void {
    if (this.flushTimer || this.writeInFlight) return;
    const pending = [...this.buckets.values()].filter((bucket) => bucket.pendingCount > 0);
    if (pending.length === 0) return;
    const delay = Math.max(
      0,
      Math.min(...pending.map((bucket) =>
        Math.max(0, bucket.lastEmittedAt + OWNER_CHANNEL_AUDIT_SUMMARY_MS - Date.now())
      )),
    );
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null;
      this.requestFlush(false);
    }, delay);
    this.flushTimer.unref?.();
  }

  private clearFlushTimer(): void {
    if (!this.flushTimer) return;
    clearTimeout(this.flushTimer);
    this.flushTimer = null;
  }

  private async appendBounded(batch: string): Promise<void> {
    await mkdir(dirname(this.auditPath), { recursive: true, mode: 0o700 });
    let size = 0;
    try { size = (await stat(this.auditPath)).size; } catch { /* new file */ }
    if (size + Buffer.byteLength(batch, "utf8") > OWNER_CHANNEL_AUDIT_MAX_BYTES) {
      const rotatedPath = `${this.auditPath}.1`;
      try { await unlink(rotatedPath); } catch { /* no predecessor */ }
      if (size <= OWNER_CHANNEL_AUDIT_MAX_BYTES) {
        try {
          await rename(this.auditPath, rotatedPath);
          try { await chmod(rotatedPath, 0o600); } catch { /* unsupported permissions */ }
        } catch { /* no active file */ }
      } else {
        // A log inherited from the old unbounded implementation must not become
        // an oversized predecessor on its first bounded append.
        try { await unlink(this.auditPath); } catch { /* no active file */ }
      }
    }
    await appendFile(this.auditPath, batch, { encoding: "utf8", mode: 0o600 });
    try { await chmod(this.auditPath, 0o600); } catch { /* unsupported permissions */ }
  }
}

const defaultOwnerChannelAuditor = new OwnerChannelAuditor(DEFAULT_OWNER_CHANNEL_AUDIT_PATH);
const customOwnerChannelAuditors = new Map<string, OwnerChannelAuditor>();

function ownerChannelAuditorFor(auditPath: string): OwnerChannelAuditor {
  if (auditPath === DEFAULT_OWNER_CHANNEL_AUDIT_PATH) return defaultOwnerChannelAuditor;
  let auditor = customOwnerChannelAuditors.get(auditPath);
  if (!auditor) {
    auditor = new OwnerChannelAuditor(auditPath);
    customOwnerChannelAuditors.set(auditPath, auditor);
  }
  return auditor;
}

/** Enqueue a coalesced, content-free owner-channel security decision without allocating per-event work. */
export function appendOwnerChannelAudit(
  peerId: string,
  reason: "missing_channel_key",
  auditPath = DEFAULT_OWNER_CHANNEL_AUDIT_PATH,
): void {
  ownerChannelAuditorFor(auditPath).record(peerId, { reason });
}

/**
 * Relay-backed protected owner channel with persisted replay high-waters.
 *
 * Outbound work is serialized, bounded, and persists each new send high-water
 * before the corresponding frame is exposed to the relay. Overflow detaches the
 * adapter so reconnect + session_sync can recover instead of silently losing an
 * arbitrary suffix. Inbound plaintext, AEAD failures, and replay are dropped
 * without reaching the message router. Five consecutive protected-frame failures
 * detach this adapter; the next protected frame can automatically reattach from
 * the same persisted key, while AEAD remains the authorization boundary.
 */
export class SecurePeerChannel implements PeerChannel {
  private readonly unsubscribe: () => void;
  private readonly auditor: OwnerChannelAuditor;
  private detached = false;
  private disconnectNotified = false;
  private recvSeq: bigint;
  private consecutiveOpenFailures = 0;
  private outboundTail: Promise<void> = Promise.resolve();
  private pendingOutboundFrames = 0;
  private pendingOutboundBytes = 0;
  private readonly inboundQueue: Uint8Array[] = [];
  private inboundDrain: Promise<void> | null = null;

  constructor(
    private readonly relay: RelayClient,
    private readonly remotePeerId: string,
    private readonly onMessage: (msg: ClientMessage) => void,
    private readonly options: SecurePeerChannelOptions,
  ) {
    this.recvSeq = options.recvSeq;
    this.auditor = ownerChannelAuditorFor(options.auditPath ?? DEFAULT_OWNER_CHANNEL_AUDIT_PATH);
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
    const jsonBytes = Buffer.byteLength(json, "utf8");
    if (
      this.pendingOutboundFrames >= MAX_PENDING_OWNER_OUTBOUND_FRAMES ||
      jsonBytes > MAX_PENDING_OWNER_OUTBOUND_BYTES - this.pendingOutboundBytes
    ) {
      // Never silently drop an arbitrary streaming suffix while the channel
      // appears healthy. Detach is the established recoverable fail-safe:
      // a protected app frame reattaches, then session_sync converges state.
      this.audit({ reason: "outbound_overflow" });
      this.disconnect();
      return;
    }

    // Account before allocating the promise continuation that retains `json`.
    this.pendingOutboundFrames += 1;
    this.pendingOutboundBytes += jsonBytes;
    this.outboundTail = this.outboundTail
      .then(async () => {
        // Work accepted before detach remains eligible to finish (notably the
        // best-effort bye queued immediately before listener teardown). Calls
        // made after detach are rejected at the send() boundary above.
        let nextSeq: bigint;
        try {
          const reserved = await this.options.reserveSendSeq();
          if (reserved === null) {
            this.audit({ reason: "sequence_persist_failed" });
            if (!this.detached) this.disconnect();
            return;
          }
          nextSeq = reserved;
        } catch (error) {
          this.audit({
            reason: error instanceof RangeError ? "sequence_exhausted" : "sequence_persist_failed",
          });
          if (!this.detached) this.disconnect();
          return;
        }

        let frame: Uint8Array;
        try {
          frame = seal(this.options.keys.send, nextSeq, json);
        } catch {
          // Reservation is already durable. A sealing failure leaves a safe gap.
          this.audit({ reason: "sequence_exhausted", seq: nextSeq });
          this.disconnect();
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
      })
      .catch(() => undefined)
      .finally(() => {
        this.pendingOutboundFrames -= 1;
        this.pendingOutboundBytes -= jsonBytes;
      });
  }

  /** Detach the channel's relay subscription without closing the shared relay. */
  detach(): void {
    if (this.detached) return;
    this.detached = true;
    this.unsubscribe();
    if (this.inboundQueue.length > 0) {
      this.audit({ reason: "ingress_overflow", occurrences: this.inboundQueue.length });
      this.inboundQueue.length = 0;
    }
  }

  /** Test/teardown seam: wait until queued reservation/persistence, ingress, and audit work settles. */
  async whenIdle(): Promise<void> {
    await this.outboundTail;
    while (this.inboundDrain) await this.inboundDrain;
    await this.auditor.whenIdle();
  }

  private onIngress(decoded: DecodedRelayIngress): void {
    if (this.detached || decoded.kind !== "outer" || decoded.frame.peer !== this.remotePeerId) return;
    const frame = Buffer.from(decoded.frame.ct, "base64");
    if (frame[0] !== 0x01) {
      // Plaintext is rejected before any expensive crypto and is not part of
      // the five-protected-failure detach threshold. Detach stays transient,
      // and the next protected frame still reattaches under the same key.
      this.audit({ reason: "plaintext_post_key" });
      return;
    }
    if (this.inboundQueue.length >= MAX_PENDING_OWNER_FRAMES) {
      this.audit({ reason: "ingress_overflow" });
      return;
    }
    this.inboundQueue.push(frame);
    this.ensureInboundDrain();
  }

  private ensureInboundDrain(): void {
    if (this.inboundDrain || this.detached) return;
    this.inboundDrain = this.drainInbound()
      .finally(() => {
        this.inboundDrain = null;
        if (this.inboundQueue.length > 0 && !this.detached) this.ensureInboundDrain();
      });
  }

  private async drainInbound(): Promise<void> {
    while (!this.detached) {
      const frame = this.inboundQueue.shift();
      if (!frame) return;
      await this.openAndRoute(frame);
    }
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

    let advanceResult: RecvSeqAdvanceResult;
    try {
      advanceResult = await this.options.compareAndAdvanceRecvSeq(opened.seq);
      if (this.detached) return;
    } catch {
      if (this.detached) return;
      this.audit({ reason: "sequence_persist_failed", seq: opened.seq });
      this.disconnect();
      return;
    }

    if (advanceResult === "replay") {
      // The local high-water is only a fast path. Another room/process may
      // already have advanced the durable value, so the locked comparison is
      // authoritative and must reject without regressing this channel's state.
      this.consecutiveOpenFailures += 1;
      this.audit({
        reason: "open_failed",
        seq: opened.seq,
        consecutiveFailures: this.consecutiveOpenFailures,
      });
      if (this.consecutiveOpenFailures >= MAX_OPEN_FAILURES) this.disconnect();
      return;
    }
    if (advanceResult === "stale_generation") {
      this.audit({ reason: "stale_generation", seq: opened.seq });
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
    this.auditor.record(this.remotePeerId, event);
  }
}

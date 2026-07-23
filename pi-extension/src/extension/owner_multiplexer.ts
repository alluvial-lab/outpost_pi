import {
  decodeRelayClientPayload,
  type DecodedRelayIngress,
} from "../protocol/relay_ingress.js";
import { ed25519Sign, ed25519Verify, type Ed25519Keypair } from "../pairing/crypto.js";
import { encodePeerChannelKeys } from "../pairing/storage.js";
import type { ByeReason, ClientMessage, PairErrorCode, ServerMessage } from "../protocol/types.js";
import type { PeerChannel } from "../transport/peer_channel.js";
import {
  appTranscript,
  deriveDirectionalKeys,
  generateX25519Keypair,
  piTranscript,
  x25519Shared,
} from "../transport/secure_channel.js";
import type { AttachOwnerInput, OwnerMultiplexerPort } from "./ports.js";

/** Extend a relay peer channel with explicit listener teardown owned by the multiplexer. */
export interface PeerChannelHandle extends PeerChannel {
  detach(): void;
}

/** Carry owner attachment context so reconnects preserve routing and late-attach semantics. */
export interface OwnerAttachInput extends AttachOwnerInput {
  /** Human/device name from peers.json or the pair_request. */
  peerName?: string;
  /** Persisted channel material required by the production secure adapter. */
  peerRecord?: OwnerPeerRecord;
  /** True when the owner attached while a turn/compaction is active. */
  turnActive?: boolean;
}

/** Define the callbacks required when the multiplexer creates one managed owner channel. */
export type CreateOwnerChannelInput = Omit<OwnerAttachInput, "onMessage" | "onDisconnect" | "turnActive"> & {
  peerRecord?: OwnerPeerRecord;
  onMessage(message: ClientMessage): void | Promise<void>;
  onDisconnect(peerId: string): void;
};

/** Describe a persisted owner identity supplied by the pairing adapter. */
export interface OwnerPeerRecord {
  name: string;
  remote_epk: string;
  paired_at: string;
  channel_key?: string;
  send_seq?: string;
  recv_seq?: string;
}

/** Provide a read-only owner and mesh snapshot for status projection. */
export interface OwnerMultiplexerSnapshot {
  activeOwnerCount: number;
  ownerShortIds: string[];
  lastOwnerShortId: string;
  hasGlobalPairings: boolean;
  sessionName: string | null;
  sessionPeerCount: number;
}

/** Report whether a requested owner disconnect changed the active channel set. */
export interface OwnerDisconnectResult {
  disconnected: boolean;
  activeOwnerCount: number;
}

type PairTokenStatus = "ok" | "expired" | "consumed" | "unknown";

type PairOkMessage = Extract<ServerMessage, { type: "pair_ok" }>;

type UnknownPeerErrorMessage = Extract<ServerMessage, { type: "error" }>;

type BufferedServerMessage = {
  message: ServerMessage;
  bytes: number;
};

interface OfflinePeerBuffer {
  completed: BufferedServerMessage[];
  completedBytes: number;
  current: BufferedServerMessage[];
  currentBytes: number;
  currentOverflowed: boolean;
}

/** Cap each offline owner's buffered frame count across completed and active intervals. */
export const OFFLINE_BUFFER_MAX_FRAMES = 2_048;

/** Cap each offline owner's serialized UTF-8 payload across completed and active intervals. */
export const OFFLINE_BUFFER_MAX_BYTES = 8 * 1024 * 1024;

function createOfflinePeerBuffer(): OfflinePeerBuffer {
  return {
    completed: [],
    completedBytes: 0,
    current: [],
    currentBytes: 0,
    currentOverflowed: false,
  };
}

function serializedMessageBytes(message: ServerMessage): number | null {
  try {
    const serialized = JSON.stringify(message);
    return typeof serialized === "string" ? Buffer.byteLength(serialized, "utf8") : null;
  } catch {
    return null;
  }
}

/** Supply the authoritative session identity included in a successful pairing reply. */
export interface PairingSessionSnapshot {
  sessionName: PairOkMessage["session_name"];
  sessionStartedAt: PairOkMessage["session_started_at"];
  sessionId: PairOkMessage["session_id"];
  roomId: PairOkMessage["room_id"];
  harness?: PairOkMessage["harness"];
  hostname?: PairOkMessage["hostname"];
}

/** Notify runtime observers that an owner channel became available for routing. */
export interface OwnerAttachedEvent {
  peerId: string;
  peerName: string;
  activeCount: number;
}

/** Notify runtime observers that a pairing was persisted and attached. */
export interface OwnerPairedEvent {
  peerId: string;
  peerName: string;
  pairedAt: string;
}

/** Notify fanout observers when an attached owner becomes unavailable or resumes. */
export interface OwnerFanoutPresenceEvent {
  peerId: string;
  peerShortId: string;
  state: "suspended" | "resumed";
  sinceTs?: number;
}

/** Supply channel, pairing, footer, and lifecycle callbacks owned outside the multiplexer. */
export interface OwnerMultiplexerDeps {
  createChannel(input: CreateOwnerChannelInput): PeerChannelHandle;
  refreshFooter(): void;
  listPeers(): Promise<OwnerPeerRecord[]>;
  findKnownPeer(peerId: string): Promise<OwnerPeerRecord | null>;
  consumePairToken(token: string): PairTokenStatus;
  addPeer(record: OwnerPeerRecord): Promise<void>;
  currentIdentity(): Ed25519Keypair | null;
  auditDrop(peerId: string, reason: "missing_channel_key"): void;
  onPeerPersisted(): void;
  currentPairingSession(): PairingSessionSnapshot;
  makeUnknownPeerError(): UnknownPeerErrorMessage;
  onOwnerAttached(event: OwnerAttachedEvent): void;
  onOwnerPaired(event: OwnerPairedEvent): void;
  onFanoutPresenceChanged?(event: OwnerFanoutPresenceEvent): void;
}

/** Carry one transport-decoded owner envelope and its routing dependencies. */
export interface OwnerOuterFrameInput {
  ingress: Extract<DecodedRelayIngress, { kind: "outer" }>;
  roomId?: string;
  turnActive(): boolean;
  isCurrent(): boolean;
  onMessage(message: ClientMessage, sender: PeerChannel): void | Promise<void>;
  onDisconnect(peerId: string): void;
  sendToPeer(peerId: string, message: ServerMessage): void;
}

function isPairRequestMessage(message: ClientMessage): message is Extract<ClientMessage, { type: "pair_request" }> {
  if (message.type !== "pair_request") return false;
  const record = message as unknown as Record<string, unknown>;
  return (
    typeof record.id === "string" &&
    typeof record.token === "string" &&
    typeof record.device_name === "string"
  );
}

function decodeCanonicalBase64(value: unknown, bytes: number): Uint8Array | null {
  if (typeof value !== "string") return null;
  const decoded = Buffer.from(value, "base64");
  if (decoded.length !== bytes || decoded.toString("base64") !== value) return null;
  return Uint8Array.from(decoded);
}

function pairErrorForStatus(status: Exclude<PairTokenStatus, "ok">): { code: PairErrorCode; message: string } {
  const code: PairErrorCode =
    status === "expired" ? "token_expired"
    : status === "consumed" ? "token_consumed"
    : "token_unknown";
  const message =
    code === "token_expired" ? "Ephemeral token expired. Generate a new QR with /outpost-pi pair."
    : code === "token_consumed" ? "Token already consumed by another pair_request."
    : "Token was not issued by this Pi.";
  return { code, message };
}

/**
 * Owns the app-owner channel registry for one pi-extension runtime.
 *
 * The relay WebSocket remains owned by the relay transport; each
 * PlainPeerChannel remains the low-level relay-backed adapter. This module owns
 * only the per-owner channel lifetime, derived paired state, fanout, and the
 * owner ingress decisions that select pairing, reconnect attach, or unknown-peer
 * responses for relay outer envelopes.
 */
export class OwnerMultiplexer implements OwnerMultiplexerPort {
  private readonly channels = new Map<string, PeerChannelHandle>();
  private readonly peerIdsByChannel = new Map<PeerChannelHandle, string>();
  private readonly messageRouters = new Map<PeerChannelHandle, OwnerAttachInput["onMessage"]>();
  private readonly offlinePeerIds = new Set<string>();
  private readonly offlineBuffers = new Map<string, OfflinePeerBuffer>();
  private readonly flushedCompactionKeysByPeer = new Map<string, Set<string>>();
  private peerShort = "";
  private lateAttachPeerIds = new Set<string>();
  private hasGlobalPairings = false;
  private sessionName: string | null = null;
  private sessionPeerCount = 0;

  constructor(private readonly deps: OwnerMultiplexerDeps) {}

  activeCount(): number {
    return this.channels.size;
  }

  peerHint(): string {
    return this.peerShort;
  }

  async refreshPairingsCache(): Promise<void> {
    try {
      const peers = await this.deps.listPeers();
      this.hasGlobalPairings = peers.length > 0;
      this.deps.refreshFooter();
    } catch {
      // Keep the prior cache value; peers.json/keyring failures should not make
      // footer/status flicker to a false "first pairing" state.
    }
  }

  setMeshSession(name: string | null): void {
    this.sessionName = name;
  }

  setSessionPeerCount(count: number): void {
    this.sessionPeerCount = count;
  }

  snapshot(): OwnerMultiplexerSnapshot {
    return {
      activeOwnerCount: this.channels.size,
      ownerShortIds: [...this.channels.keys()].map((peerId) => peerId.slice(0, 8)),
      lastOwnerShortId: this.peerShort,
      hasGlobalPairings: this.hasGlobalPairings,
      sessionName: this.sessionName,
      sessionPeerCount: this.sessionPeerCount,
    };
  }

  has(peerId: string): boolean {
    return this.channels.has(peerId);
  }

  get(peerId: string): PeerChannel | undefined {
    return this.channels.get(peerId);
  }

  peerIds(): readonly string[] {
    return [...this.channels.keys()];
  }

  entries(): readonly { peerId: string; channel: PeerChannel }[] {
    return [...this.channels.entries()].map(([peerId, channel]) => ({ peerId, channel }));
  }

  private emitFanoutPresenceChanged(peerId: string, state: OwnerFanoutPresenceEvent["state"], sinceTs?: number): void {
    this.deps.onFanoutPresenceChanged?.({
      peerId,
      peerShortId: peerId.slice(0, 8),
      state,
      ...(sinceTs === undefined ? {} : { sinceTs }),
    });
  }

  async handleOuterFrame(input: OwnerOuterFrameInput): Promise<boolean> {
    const decoded = input.ingress;
    const outer = decoded.frame;
    if (!input.isCurrent()) return false;
    // NOTE: do NOT re-check `outer.room` against `input.roomId` here. The
    // relay's `dispatch_outer` rewrites the DELIVERED envelope's `room` to the
    // SENDER's authenticated room_id (anti-spoof: "recipient sees sender's
    // room_id"), not the destination room the sender targeted. An app (and
    // any peer that authenticates in `main`) targeting a Pi in its cwd-room
    // delivers `outer.room = 'main'`, which never equals the Pi's own room —
    // so a recipient-side guard here would silently drop EVERY cross-room
    // message: the pair_request first (app times out), then all post-pair
    // app traffic. Room routing was already enforced by the relay's
    // `(peer, room)` lookup in `send_to_room` — this message arrived because
    // the sender's destination room matched this Pi's registered room. The
    // sender's identity is established by Ed25519 auth at the relay, not by
    // this rewritten field, so there is no spoofing surface to re-defend.
    const inner = decodeRelayClientPayload(decoded.payloadUtf8);
    if (inner?.type === "pair_request") {
      if (!isPairRequestMessage(inner)) return false;
      // A valid plaintext re-pair is allowed even while an older secure channel
      // is attached; successful persistence replaces and detaches that channel.
      await this.handlePairRequest(input, outer.peer, inner);
      return true;
    }
    if (this.channels.has(outer.peer)) return false;

    const known = await this.deps.findKnownPeer(outer.peer);
    if (!input.isCurrent()) return false;
    if (known) {
      if (!known.channel_key) {
        this.deps.auditDrop(outer.peer, "missing_channel_key");
        return false;
      }
      this.attach({
        peerId: outer.peer,
        peerName: known.name,
        peerRecord: known,
        roomId: input.roomId,
        turnActive: input.turnActive(),
        onMessage: input.onMessage,
        onDisconnect: input.onDisconnect,
      });
      this.deps.onOwnerAttached({ peerId: outer.peer, peerName: known.name, activeCount: this.activeCount() });
      // RelayTransport publishes this same decoded ingress to the freshly
      // attached channel after this async handler returns. Never route the
      // plaintext decode here: established owners must pass SecurePeerChannel.
      return false;
    }

    if (inner) input.sendToPeer(outer.peer, this.deps.makeUnknownPeerError());
    return false;
  }

  async handlePairRequest(
    input: OwnerOuterFrameInput,
    peerId: string,
    inner: Extract<ClientMessage, { type: "pair_request" }>,
  ): Promise<void> {
    const sendError = (code: PairErrorCode, message: string) => {
      input.sendToPeer(peerId, { type: "pair_error", in_reply_to: inner.id, code, message });
    };

    // Verify the signed app DH share before touching the single-use token.
    const identity = this.deps.currentIdentity();
    const ownerEdPk = decodeCanonicalBase64(peerId, 32);
    const appDhPk = decodeCanonicalBase64(inner.dh_pk, 32);
    const appDhSig = decodeCanonicalBase64(inner.dh_sig, 64);
    let validDhSignature = false;
    if (identity && ownerEdPk && appDhPk && appDhSig) {
      try {
        validDhSignature = ed25519Verify(
          ownerEdPk,
          appTranscript(inner.token, appDhPk, identity.publicKey),
          appDhSig,
        );
      } catch {
        validDhSignature = false;
      }
    }
    if (!validDhSignature) {
      sendError("bad_dh_sig", "Invalid or missing owner channel key signature.");
      return;
    }

    const status = this.deps.consumePairToken(inner.token);
    if (status !== "ok") {
      const error = pairErrorForStatus(status);
      sendError(error.code, error.message);
      return;
    }

    const pairedAt = new Date().toISOString();
    let record: OwnerPeerRecord;
    let piDhPk: Uint8Array;
    let piDhSig: Uint8Array;
    try {
      const piDh = generateX25519Keypair();
      piDhPk = piDh.pk;
      const shared = x25519Shared(piDh.sk, appDhPk!);
      const keys = deriveDirectionalKeys(shared, inner.token, "pi");
      piDhSig = ed25519Sign(
        identity!.secretKey,
        piTranscript(inner.token, appDhPk!, piDhPk, ownerEdPk!),
      );
      record = {
        name: inner.device_name,
        remote_epk: peerId,
        paired_at: pairedAt,
        channel_key: encodePeerChannelKeys(keys),
        send_seq: "0",
        recv_seq: "0",
      };
      // Persist key material before the plaintext pair_ok makes the app adopt it.
      await this.deps.addPeer(record);
      this.deps.onPeerPersisted();
    } catch (err) {
      if (input.isCurrent()) {
        sendError("internal_error", `Failed to establish protected channel: ${String(err)}`);
      }
      return;
    }
    if (!input.isCurrent()) return;

    const session = this.deps.currentPairingSession();
    input.sendToPeer(peerId, {
      type: "pair_ok",
      in_reply_to: inner.id,
      session_name: session.sessionName,
      session_started_at: session.sessionStartedAt,
      session_id: session.sessionId,
      room_id: session.roomId,
      ...(session.harness ? { harness: session.harness } : {}),
      ...(session.hostname ? { hostname: session.hostname } : {}),
      dh_pk: Buffer.from(piDhPk).toString("base64"),
      dh_sig: Buffer.from(piDhSig).toString("base64"),
    });

    this.attach({
      peerId,
      peerName: inner.device_name,
      peerRecord: record,
      roomId: input.roomId,
      turnActive: input.turnActive(),
      onMessage: input.onMessage,
      onDisconnect: input.onDisconnect,
    });
    this.deps.onOwnerAttached({ peerId, peerName: inner.device_name, activeCount: this.activeCount() });
    this.deps.onOwnerPaired({ peerId, peerName: inner.device_name, pairedAt });
  }

  attach(input: OwnerAttachInput): PeerChannel {
    // Idempotent reattach: tear down the stale per-owner listener before
    // installing a fresh channel for the same owner peer id. A fresh attach is
    // also an online signal: clear any stale relay-offline suspension so a
    // reconnect during an active turn resumes fan-out immediately.
    const wasOffline = this.offlinePeerIds.has(input.peerId);
    this.detach(input.peerId);

    let channel: PeerChannelHandle | null = null;
    channel = this.deps.createChannel({
      peerId: input.peerId,
      roomId: input.roomId,
      peerRecord: input.peerRecord,
      onMessage: (message) => this.routeFrom(channel as PeerChannelHandle, message),
      onDisconnect: (peerId) => {
        this.detach(peerId);
        input.onDisconnect?.(peerId);
      },
    });

    this.channels.set(input.peerId, channel);
    this.peerIdsByChannel.set(channel, input.peerId);
    this.messageRouters.set(channel, input.onMessage);
    this.peerShort = input.peerId.slice(0, 8);
    if (wasOffline) this.emitFanoutPresenceChanged(input.peerId, "resumed");
    if (input.turnActive) this.lateAttachPeerIds.add(input.peerId);
    this.deps.refreshFooter();
    return channel;
  }

  disconnectOwner(peerId?: string): OwnerDisconnectResult {
    const target = peerId ?? this.peerIds().at(-1);
    if (!target || !this.channels.has(target)) {
      return { disconnected: false, activeOwnerCount: this.activeCount() };
    }
    this.detach(target);
    return { disconnected: true, activeOwnerCount: this.activeCount() };
  }

  revokeOwner(peerId: string): void {
    this.detach(peerId, "session_replaced");
  }

  detach(peerId: string, reason?: ByeReason): void {
    const channel = this.channels.get(peerId);
    if (!channel) return;

    if (reason) {
      try { channel.send({ type: "bye", reason }); } catch { /* best-effort per owner channel */ }
    }

    try { channel.detach(); } catch { /* best-effort per owner channel */ }

    this.channels.delete(peerId);
    this.peerIdsByChannel.delete(channel);
    this.messageRouters.delete(channel);
    this.lateAttachPeerIds.delete(peerId);
    this.offlinePeerIds.delete(peerId);
    this.offlineBuffers.delete(peerId);
    this.flushedCompactionKeysByPeer.delete(peerId);

    if (this.peerShort === peerId.slice(0, 8)) {
      const next = this.channels.keys().next().value as string | undefined;
      this.peerShort = next ? next.slice(0, 8) : "";
    }
    this.deps.refreshFooter();
  }

  detachAll(reason?: ByeReason): void {
    for (const peerId of [...this.channels.keys()]) {
      this.detach(peerId, reason);
    }
    this.lateAttachPeerIds.clear();
    this.offlinePeerIds.clear();
    this.offlineBuffers.clear();
    this.flushedCompactionKeysByPeer.clear();
    this.peerShort = "";
    this.deps.refreshFooter();
  }

  detachAllForRelayDrop(): void {
    this.detachAll();
  }

  markPeerOffline(peerId: string, sinceTs?: number): boolean {
    if (!this.channels.has(peerId) || this.offlinePeerIds.has(peerId)) return false;
    this.offlinePeerIds.add(peerId);
    this.lateAttachPeerIds.delete(peerId);
    this.emitFanoutPresenceChanged(peerId, "suspended", sinceTs);
    return true;
  }

  markPeerOnline(peerId: string): boolean {
    if (!this.offlinePeerIds.has(peerId)) return false;

    const channel = this.channels.get(peerId);
    const buffer = this.offlineBuffers.get(peerId);
    if (channel && buffer) {
      let next = this.takeNextBufferedMessage(buffer);
      while (
        next &&
        this.channels.get(peerId) === channel &&
        this.offlinePeerIds.has(peerId) &&
        this.offlineBuffers.get(peerId) === buffer
      ) {
        try {
          channel.send(next);
          this.rememberFlushedCompaction(peerId, next);
        } catch { /* best-effort per owner channel */ }
        next = this.takeNextBufferedMessage(buffer);
      }
    }

    this.offlineBuffers.delete(peerId);
    if (this.offlinePeerIds.delete(peerId)) {
      this.emitFanoutPresenceChanged(peerId, "resumed");
    }
    return true;
  }

  isPeerOffline(peerId: string): boolean {
    return this.offlinePeerIds.has(peerId);
  }

  broadcast(message: ServerMessage): void {
    for (const [peerId, channel] of this.channels) {
      if (this.offlinePeerIds.has(peerId)) {
        this.bufferOfflineMessage(peerId, message);
        continue;
      }
      try { channel.send(message); } catch { /* best-effort per owner channel */ }
    }
  }

  /** Seal each offline peer's active interval at the canonical turn boundary. */
  completeOfflineTurn(): void {
    for (const buffer of this.offlineBuffers.values()) {
      if (!buffer.currentOverflowed && buffer.current.length > 0) {
        buffer.completed = buffer.current;
        buffer.completedBytes = buffer.currentBytes;
      }
      buffer.current = [];
      buffer.currentBytes = 0;
      buffer.currentOverflowed = false;
    }
  }

  private takeNextBufferedMessage(buffer: OfflinePeerBuffer): ServerMessage | null {
    const completed = buffer.completed.shift();
    if (completed) {
      buffer.completedBytes -= completed.bytes;
      return completed.message;
    }
    const current = buffer.current.shift();
    if (current) {
      buffer.currentBytes -= current.bytes;
      return current.message;
    }
    return null;
  }

  private bufferOfflineMessage(peerId: string, message: ServerMessage): void {
    let buffer = this.offlineBuffers.get(peerId);
    if (!buffer) {
      buffer = createOfflinePeerBuffer();
      this.offlineBuffers.set(peerId, buffer);
    }
    if (buffer.currentOverflowed) return;

    const bytes = serializedMessageBytes(message);
    const wouldExceedCombinedCap = bytes === null ||
      buffer.completed.length + buffer.current.length + 1 > OFFLINE_BUFFER_MAX_FRAMES ||
      buffer.completedBytes + buffer.currentBytes + bytes > OFFLINE_BUFFER_MAX_BYTES;

    if (wouldExceedCombinedCap) {
      buffer.completed = [];
      buffer.completedBytes = 0;
    }

    const currentCannotFit = bytes === null ||
      buffer.current.length + 1 > OFFLINE_BUFFER_MAX_FRAMES ||
      buffer.currentBytes + bytes > OFFLINE_BUFFER_MAX_BYTES;
    if (currentCannotFit) {
      buffer.current = [];
      buffer.currentBytes = 0;
      buffer.currentOverflowed = true;
      return;
    }

    buffer.current.push({ message, bytes });
    buffer.currentBytes += bytes;
  }

  private rememberFlushedCompaction(peerId: string, message: ServerMessage): void {
    if (message.type !== "compaction" || message.ts === undefined) return;
    let keys = this.flushedCompactionKeysByPeer.get(peerId);
    if (!keys) {
      keys = new Set<string>();
      this.flushedCompactionKeysByPeer.set(peerId, keys);
    }
    keys.add(`${message.session_id ?? ""}:${message.ts}`);
  }

  /**
   * Suppress compactions already delivered by an online-first buffer flush.
   *
   * User, assistant, and tool replay paths already converge through stable
   * identities or projection keys. Compaction is the exception: the app's
   * live and history paths derive different row ids, so replaying a flushed
   * compaction would retain both rows. Keep this peer-scoped arbitration for
   * the managed channel lifetime so every later sync remains idempotent.
   */
  arbitrateSessionHistory(
    sender: PeerChannel,
    history: Extract<ServerMessage, { type: "session_history" }>,
  ): Extract<ServerMessage, { type: "session_history" }> {
    const channel = sender as PeerChannelHandle;
    const peerId = this.peerIdsByChannel.get(channel);
    if (!peerId || this.channels.get(peerId) !== channel) return history;
    const flushedKeys = this.flushedCompactionKeysByPeer.get(peerId);
    if (!flushedKeys || flushedKeys.size === 0) return history;

    const events = history.events.filter((event) =>
      event.type !== "compaction" || !flushedKeys.has(`${history.session_id ?? ""}:${event.ts}`)
    );
    return events.length === history.events.length ? history : { ...history, events };
  }

  routeFrom(sender: PeerChannel, message: ClientMessage): void | Promise<void> {
    const channel = sender as PeerChannelHandle;
    const peerId = this.peerIdsByChannel.get(channel);
    if (!peerId || this.channels.get(peerId) !== channel) return;
    if (message.type === "session_sync" && this.offlinePeerIds.has(peerId)) {
      this.offlineBuffers.delete(peerId);
      this.markPeerOnline(peerId);
    }
    const route = this.messageRouters.get(channel);
    return route?.(message, sender);
  }

  lateAttachTargets(): readonly PeerChannel[] {
    const targets = [...this.lateAttachPeerIds]
      .map((peerId) => this.channels.get(peerId))
      .filter((channel): channel is PeerChannelHandle => !!channel);
    this.lateAttachPeerIds.clear();
    return targets;
  }

  lateAttachEntries(): readonly { peerId: string; channel: PeerChannel }[] {
    const targets = [...this.lateAttachPeerIds]
      .map((peerId) => {
        const channel = this.channels.get(peerId);
        return channel ? { peerId, channel } : null;
      })
      .filter((entry): entry is { peerId: string; channel: PeerChannelHandle } => !!entry);
    this.lateAttachPeerIds.clear();
    return targets;
  }
}

/** Create the runtime owner port with one multiplexer-owned channel registry. */
export function createOwnerMultiplexerPort(
  deps: OwnerMultiplexerDeps,
): OwnerMultiplexerPort {
  return new OwnerMultiplexer(deps);
}

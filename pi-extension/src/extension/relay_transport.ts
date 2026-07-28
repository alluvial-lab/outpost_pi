import type { ByeReason, ThinkingLevel } from "../protocol/types.js";
import {
  isRelayPostAuthControlFrame,
  RELAY_MAX_RAW_MESSAGE_BYTES,
  type RelayControlFrame,
  type RelayControlFrameRoomMetaUpdate,
} from "../protocol/generated/protocol.generated.js";
import {
  decodeRelayIngress,
  type DecodedRelayIngress,
  type RelayServerControlFrame,
} from "../protocol/relay_ingress.js";
import type { Ed25519Keypair } from "../pairing/crypto.js";
import {
  compareAndAdvanceRecvSeq,
  decodePeerChannelKeys,
  parsePeerChannelSequence,
  reserveSendSeq,
} from "../pairing/storage.js";
import {
  REACHABILITY_RELAY_LIVENESS_CHECK_MS,
  REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS,
  reachabilityBackoffMs,
} from "../reachability/reachability_contract.js";
import type { RelayClient, RoomMeta } from "../transport/relay_client.js";
import {
  appendRelayDispatchOverflowAudit,
  type RelayDispatchOverflowAudit,
} from "../transport/relay_dispatch_audit.js";
import {
  claimRelayIngressFanout,
  publishRelayIngress,
} from "../transport/relay_ingress_fanout.js";
import { PlainPeerChannel, SecurePeerChannel } from "../transport/peer_channel.js";
import type {
  CrossPcBridgeInput,
  RelayPeerChannel,
  RelayPeerChannelInput,
  RelayStartInput,
  RelayStartResult,
  RelayTransportPort,
} from "./ports.js";
import type { RelayConnectivity } from "./types.js";

/** Project relay connectivity into the status snapshot emitted to external observers. */
export interface RelayStateSnapshot {
  status: RelayConnectivity;
  connected: boolean;
  relayUrl?: string;
  room?: string;
}

/** Extend relay startup with epoch guards and callbacks owned by the runtime coordinator. */
export interface RelayTransportStartInput extends RelayStartInput {
  isDisposed?: () => boolean;
  onUnexpectedClose?: () => void;
  onConnected?: (relay: RelayClient) => void | Promise<void>;
}

/** Report that relay startup completed after its owning runtime epoch was disposed. */
export class RelayStartAbortedError extends Error {
  constructor() {
    super("relay start aborted");
    this.name = "RelayStartAbortedError";
  }
}

/** Supply transport construction, timing, and state publication adapters to the relay port. */
export interface RelayTransportDeps {
  createRelay(url: string, keypair: Ed25519Keypair): RelayClient;
  toWebSocketUrl(url: string): string;
  backoffMs(attempt: number): number;
  now(): number;
  setTimer(cb: () => void, delayMs: number): ReturnType<typeof setTimeout>;
  clearTimer(timer: ReturnType<typeof setTimeout>): void;
  emitRelayState(snapshot: RelayStateSnapshot): void;
  auditDispatchOverflow?(event: RelayDispatchOverflowAudit): void | Promise<void>;
}

/** Expose the concrete relay adapter's extended startup, control-frame, and diagnostics contract. */
export interface RelayTransportAdapter extends Omit<RelayTransportPort, "start"> {
  start(input: RelayTransportStartInput): Promise<RelayStartResult>;
  onControlFrame(handler: (frame: RelayControlFrame) => void | Promise<void>): () => void;
  emitRelayState(force?: boolean): void;
  hasPendingReconnect(): boolean;
  currentRelayUrl(): string | null;
}

export const RELAY_TRANSPORT_REACHABILITY = {
  backoffMs: reachabilityBackoffMs,
  livenessTimeoutMs: REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS,
  livenessCheckMs: REACHABILITY_RELAY_LIVENESS_CHECK_MS,
} as const;

/**
 * Maximum data-plane frames retained by one relay connection's dispatch FIFO.
 * 256 leaves ample room for ordinary reconnect replay bursts (normally tens).
 */
export const MAX_PENDING_RELAY_DISPATCH_FRAMES = 256;
/**
 * Maximum raw UTF-8 data-plane bytes retained by one relay connection's dispatch FIFO.
 * 8 MiB admits a schema-maximum owner frame plus normal text replay while bounding images.
 */
export const MAX_PENDING_RELAY_DISPATCH_BYTES = 8 * 1024 * 1024;
/**
 * Maximum control frames retained by one relay connection's dispatch FIFO.
 * Presence/room metadata is low-frequency; 64 still absorbs generous bursts.
 */
export const MAX_PENDING_RELAY_CONTROL_FRAMES = 64;
/**
 * Maximum raw UTF-8 control bytes retained by one relay connection's dispatch FIFO.
 * 256 KiB accommodates large presence snapshots without permitting an unbounded flood.
 */
export const MAX_PENDING_RELAY_CONTROL_BYTES = 256 * 1024;
/** Emit a counted overflow summary after this many suppressed drops. */
export const RELAY_DISPATCH_AUDIT_SUMMARY_EVENTS = 100;
const RELAY_DISPATCH_AUDIT_SUMMARY_MS = 5_000;

/** Decode one generated relay control DTO at the transport boundary. */
export function decodeRelayControlFrame(line: string): RelayServerControlFrame | null {
  if (Buffer.byteLength(line, "utf8") > RELAY_MAX_RAW_MESSAGE_BYTES) return null;
  try {
    const parsed = JSON.parse(line) as unknown;
    return isRelayPostAuthControlFrame(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

/** Create the lifecycle-owned relay adapter with reconnect and cross-PC bridge teardown. */
export function createRelayTransportPort(deps: RelayTransportDeps): RelayTransportAdapter {
  const backoffMs = deps.backoffMs ?? reachabilityBackoffMs;
  const auditDispatchOverflow = deps.auditDispatchOverflow ?? appendRelayDispatchOverflowAudit;
  let relay: RelayClient | null = null;
  let relayUrl: string | null = null;
  let keypair: Ed25519Keypair | null = null;
  let roomId: string | null = null;
  let roomMeta: RoomMeta | null = null;
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  let reconnectAttempt = 0;
  let lastStatus: RelayConnectivity | null = null;
  let lastEmittedStatus: RelayConnectivity | null = null;
  let lastStatusChangedAt = deps.now();
  let stopping = false;
  let crossPcBridgeInput: CrossPcBridgeInput | null = null;
  let isDisposed: (() => boolean) | null = null;
  let onUnexpectedClose: (() => void) | null = null;
  let onConnected: ((relay: RelayClient) => void | Promise<void>) | null = null;
  type DecodedOuterIngress = Extract<DecodedRelayIngress, { kind: "outer" }>;
  const outerMessageHandlers = new Set<(
    ingress: DecodedOuterIngress,
    isCurrent: () => boolean,
  ) => boolean | void | Promise<boolean | void>>();
  const controlFrameHandlers = new Set<(frame: RelayControlFrame) => void | Promise<void>>();
  type RelayBinding = {
    relay: RelayClient;
    generation: number;
    onMessage(line: string): void;
    onClose(): void;
    flushOverflowAudit(): void;
    releasePendingDispatch(): void;
    releaseIngressFanout(): void;
  };
  let relayBinding: RelayBinding | null = null;
  let nextRelayGeneration = 1;
  type BridgeAttachment = {
    relay: RelayClient;
    relayUrl: string;
    meshNode: NonNullable<ReturnType<CrossPcBridgeInput["meshNode"]>>;
    keyId: string;
    epoch: number;
    pending: Promise<void>;
  };
  let activeBridge: BridgeAttachment | null = null;
  let bridgeEpoch = 0;

  function setLastStatus(status: RelayConnectivity): RelayConnectivity {
    if (status !== lastStatus) {
      lastStatus = status;
      lastStatusChangedAt = deps.now();
    }
    return status;
  }

  function status(): RelayConnectivity {
    void lastStatusChangedAt;
    if (!relayUrl) return setLastStatus("disconnected");
    return setLastStatus(relay ? "connected" : "reconnecting");
  }

  function snapshot(): RelayStateSnapshot {
    const nextStatus = status();
    return {
      status: nextStatus,
      connected: nextStatus === "connected",
      ...(relayUrl ? { relayUrl } : {}),
      ...(roomId ? { room: roomId } : {}),
    };
  }

  function emitRelayState(force = false): void {
    const nextStatus = status();
    if (!force && nextStatus === lastEmittedStatus) return;
    lastEmittedStatus = nextStatus;
    deps.emitRelayState(snapshot());
  }

  function connectionIsCurrent(binding: RelayBinding): boolean {
    return relayBinding?.generation === binding.generation &&
      relay === binding.relay && !stopping && !isDisposed?.();
  }

  function bindRelay(next: RelayClient): void {
    type DispatchQueue = RelayDispatchOverflowAudit["queue"];
    type OverflowState = {
      readonly queue: DispatchQueue;
      readonly maxPendingFrames: number;
      readonly maxPendingBytes: number;
      droppedFrames: number;
      droppedBytes: number;
      auditEmitted: boolean;
      timer: ReturnType<typeof setTimeout> | null;
    };
    type RetainedDispatch = {
      readonly queue: DispatchQueue;
      readonly lineBytes: number;
      line: string | null;
      controlFrame: RelayControlFrame | null;
      accounted: boolean;
    };

    let dispatchDrain: Promise<void> | null = null;
    let activeDispatch: RetainedDispatch | null = null;
    let bindingAlive = true;
    let pendingDataFrames = 0;
    let pendingDataBytes = 0;
    let pendingControlFrames = 0;
    let pendingControlBytes = 0;
    const pendingDispatches: RetainedDispatch[] = [];
    const dataOverflow: OverflowState = {
      queue: "data",
      maxPendingFrames: MAX_PENDING_RELAY_DISPATCH_FRAMES,
      maxPendingBytes: MAX_PENDING_RELAY_DISPATCH_BYTES,
      droppedFrames: 0,
      droppedBytes: 0,
      auditEmitted: false,
      timer: null,
    };
    const controlOverflow: OverflowState = {
      queue: "control",
      maxPendingFrames: MAX_PENDING_RELAY_CONTROL_FRAMES,
      maxPendingBytes: MAX_PENDING_RELAY_CONTROL_BYTES,
      droppedFrames: 0,
      droppedBytes: 0,
      auditEmitted: false,
      timer: null,
    };

    const flushOverflow = (state: OverflowState): void => {
      if (state.timer) {
        deps.clearTimer(state.timer);
        state.timer = null;
      }
      if (state.droppedFrames === 0) return;
      const event = {
        queue: state.queue,
        droppedFrames: state.droppedFrames,
        droppedBytes: state.droppedBytes,
        maxPendingFrames: state.maxPendingFrames,
        maxPendingBytes: state.maxPendingBytes,
      } satisfies RelayDispatchOverflowAudit;
      state.droppedFrames = 0;
      state.droppedBytes = 0;
      state.auditEmitted = true;
      try {
        void Promise.resolve(auditDispatchOverflow(event)).catch(() => undefined);
      } catch {
        // Best-effort audit cannot turn ingress rejection into an availability failure.
      }
    };

    const flushOverflowAudit = (): void => {
      flushOverflow(dataOverflow);
      flushOverflow(controlOverflow);
    };

    const recordOverflow = (state: OverflowState, lineBytes: number): void => {
      state.droppedFrames += 1;
      state.droppedBytes += lineBytes;
      if (!state.auditEmitted || state.droppedFrames >= RELAY_DISPATCH_AUDIT_SUMMARY_EVENTS) {
        flushOverflow(state);
        return;
      }
      if (state.timer) return;
      state.timer = deps.setTimer(
        () => flushOverflow(state),
        RELAY_DISPATCH_AUDIT_SUMMARY_MS,
      );
      state.timer.unref?.();
    };

    const releaseDispatch = (work: RetainedDispatch): void => {
      work.line = null;
      work.controlFrame = null;
      if (!work.accounted) return;
      work.accounted = false;
      if (work.queue === "control") {
        pendingControlFrames -= 1;
        pendingControlBytes -= work.lineBytes;
      } else {
        pendingDataFrames -= 1;
        pendingDataBytes -= work.lineBytes;
      }
    };

    const releasePendingDispatch = (): void => {
      bindingAlive = false;
      // Reconnect invalidates this generation. Queued app frames are
      // recoverable through reconnect + session_sync (pairing retries through
      // its existing timeout), so discard the explicit queue and release raw
      // strings/DTOs immediately. Work already inside a handler continues;
      // its finalizer is idempotent against the zeroed accounting.
      if (activeDispatch) releaseDispatch(activeDispatch);
      for (const work of pendingDispatches.splice(0)) releaseDispatch(work);
    };

    const drainDispatches = async (): Promise<void> => {
      while (bindingAlive) {
        const work = pendingDispatches.shift();
        if (!work) return;
        activeDispatch = work;
        try {
          if (work.queue === "control") {
            const frame = work.controlFrame;
            work.controlFrame = null;
            if (frame) await dispatchRelayControlFrame(frame);
          } else {
            const line = work.line;
            work.line = null;
            if (line) {
              await dispatchRelayMessage(next, line, () => connectionIsCurrent(binding));
            }
          }
        } catch {
          // One handler failure cannot poison accounting or later accepted work.
        } finally {
          releaseDispatch(work);
          if (activeDispatch === work) activeDispatch = null;
        }
      }
    };

    const ensureDispatchDrain = (): void => {
      if (dispatchDrain || !bindingAlive) return;
      dispatchDrain = drainDispatches().finally(() => {
        dispatchDrain = null;
        if (pendingDispatches.length > 0 && bindingAlive) ensureDispatchDrain();
      });
    };

    const enqueue = (work: RetainedDispatch): void => {
      if (work.queue === "control") {
        pendingControlFrames += 1;
        pendingControlBytes += work.lineBytes;
      } else {
        pendingDataFrames += 1;
        pendingDataBytes += work.lineBytes;
      }
      // Both classes deliberately share this explicit FIFO. Presence updates
      // can affect owner fanout state, so retaining WebSocket order across
      // control and data avoids a frame overtaking the transition preceding it.
      // Independent budgets plus queue clearing on unbind prevent either class
      // or stale reconnect generations from retaining memory without bound.
      pendingDispatches.push(work);
      ensureDispatchDrain();
    };

    const binding = {
      relay: next,
      generation: nextRelayGeneration++,
      onMessage: (line: string) => {
        // Outer envelopes cannot contain a top-level `type` key (closed
        // generated shape), so ordinary data avoids even a speculative parse.
        const lineBytes = Buffer.byteLength(line, "utf8");
        const controlFrame = line.includes('"type"') ? decodeRelayControlFrame(line) : null;
        if (controlFrame) {
          if (
            pendingControlFrames >= MAX_PENDING_RELAY_CONTROL_FRAMES ||
            lineBytes > MAX_PENDING_RELAY_CONTROL_BYTES - pendingControlBytes
          ) {
            recordOverflow(controlOverflow, lineBytes);
            return;
          }
          enqueue({
            queue: "control",
            lineBytes,
            line: null,
            controlFrame,
            accounted: true,
          });
          return;
        }

        if (
          pendingDataFrames >= MAX_PENDING_RELAY_DISPATCH_FRAMES ||
          lineBytes > MAX_PENDING_RELAY_DISPATCH_BYTES - pendingDataBytes
        ) {
          // Drop only the NEW raw frame so every accepted frame remains strict
          // FIFO. Known owners recover through session_sync; pairing retries
          // through its existing timeout.
          recordOverflow(dataOverflow, lineBytes);
          return;
        }

        // Admission precedes work-cell allocation. The explicit queue lets
        // unbind remove every queued cell while the active handler is blocked.
        enqueue({
          queue: "data",
          lineBytes,
          line,
          controlFrame: null,
          accounted: true,
        });
      },
      onClose: () => onRelayClose(binding),
      flushOverflowAudit,
      releasePendingDispatch,
      releaseIngressFanout: claimRelayIngressFanout(next),
    } satisfies RelayBinding;
    relayBinding = binding;
    next.on("message", binding.onMessage);
    next.on("close", binding.onClose);
  }

  function unbindRelay(current: RelayClient): void {
    const binding = relayBinding;
    if (!binding || binding.relay !== current) return;
    relayBinding = null;
    current.off("close", binding.onClose);
    current.off("message", binding.onMessage);
    binding.releasePendingDispatch();
    binding.flushOverflowAudit();
    binding.releaseIngressFanout();
  }

  function clearReconnectTimer(): void {
    if (reconnectTimer === null) return;
    deps.clearTimer(reconnectTimer);
    reconnectTimer = null;
  }

  function onRelayClose(binding: RelayBinding): void {
    if (!connectionIsCurrent(binding) || !relayUrl) return;
    detachCrossPcBridge();
    unbindRelay(binding.relay);
    relay = null;
    onUnexpectedClose?.();
    emitRelayState();
    scheduleReconnect();
  }

  function scheduleReconnect(): void {
    if (reconnectTimer !== null) return;
    if (!relayUrl || !keypair) return;
    if (status() === "disconnected") return;
    const delayMs = backoffMs(reconnectAttempt);
    reconnectAttempt += 1;
    reconnectTimer = deps.setTimer(() => {
      reconnectTimer = null;
      void attemptReconnect();
    }, delayMs);
  }

  async function attemptReconnect(): Promise<void> {
    if (status() === "disconnected" || !relayUrl || !keypair) return;
    const nextRelay = deps.createRelay(deps.toWebSocketUrl(relayUrl), keypair);
    try {
      await nextRelay.connect({
        ...(roomId ? { roomId } : {}),
        ...(roomMeta ? { roomMeta } : {}),
      });
    } catch {
      if (status() !== "disconnected") scheduleReconnect();
      return;
    }

    if (status() === "disconnected" || isDisposed?.()) {
      nextRelay.close();
      return;
    }

    relay = nextRelay;
    reconnectAttempt = 0;
    bindRelay(nextRelay);
    if (onConnected) void onConnected(nextRelay);
    if (crossPcBridgeInput) {
      void attachCrossPcBridge(crossPcBridgeInput);
    }
    emitRelayState();
  }

  async function start(input: RelayTransportStartInput): Promise<RelayStartResult> {
    if (!input.keypair) throw new Error("outpost-pi identity not loaded");
    stopping = false;
    clearReconnectTimer();
    const nextRelay = deps.createRelay(deps.toWebSocketUrl(input.relayUrl), input.keypair);
    await nextRelay.connect({ roomId: input.roomId, roomMeta: input.roomMeta });
    if (input.isDisposed?.()) {
      nextRelay.close();
      throw new RelayStartAbortedError();
    }
    if (relay) {
      unbindRelay(relay);
      relay.close();
    }
    relay = nextRelay;
    relayUrl = input.relayUrl;
    keypair = input.keypair;
    roomId = input.roomId ?? null;
    roomMeta = input.roomMeta ?? null;
    isDisposed = input.isDisposed ?? null;
    onUnexpectedClose = input.onUnexpectedClose ?? null;
    onConnected = input.onConnected ?? null;
    reconnectAttempt = 0;
    bindRelay(nextRelay);
    if (onConnected) void onConnected(nextRelay);
    if (crossPcBridgeInput) {
      void attachCrossPcBridge(crossPcBridgeInput);
    }
    emitRelayState();
    return { roomId: input.roomId };
  }

  async function stop(_reason?: ByeReason): Promise<void> {
    stopping = true;
    clearReconnectTimer();
    reconnectAttempt = 0;
    detachCrossPcBridge();
    const current = relay;
    relay = null;
    relayUrl = null;
    keypair = null;
    roomId = null;
    roomMeta = null;
    onUnexpectedClose = null;
    onConnected = null;
    if (current) {
      unbindRelay(current);
      current.close();
    }
    emitRelayState();
  }

  function sendRoomMeta(
    patch: Partial<RoomMeta> & { working?: boolean; thinking?: ThinkingLevel },
  ): void {
    if (!roomId) return;
    if (roomMeta) roomMeta = { ...roomMeta, ...patch };
    const frame = {
      type: "room_meta_update",
      room_id: roomId,
      meta: patch,
    } satisfies RelayControlFrameRoomMetaUpdate;
    relay?.sendControl(frame);
  }

  function onOuterMessage(
    handler: (
      ingress: DecodedOuterIngress,
      isCurrent: () => boolean,
    ) => boolean | void | Promise<boolean | void>,
  ): () => void {
    outerMessageHandlers.add(handler);
    return () => {
      outerMessageHandlers.delete(handler);
    };
  }

  function onControlFrame(handler: (frame: RelayControlFrame) => void | Promise<void>): () => void {
    controlFrameHandlers.add(handler);
    return () => {
      controlFrameHandlers.delete(handler);
    };
  }

  async function dispatchRelayControlFrame(frame: RelayControlFrame): Promise<void> {
    for (const handler of controlFrameHandlers) {
      await handler(frame);
    }
  }

  async function dispatchRelayMessage(
    source: RelayClient,
    line: string,
    isCurrent: () => boolean,
  ): Promise<void> {
    let decoded: DecodedRelayIngress;
    try {
      decoded = decodeRelayIngress(line);
    } catch {
      return;
    }
    let consumed = false;
    if (decoded.kind === "control") {
      await dispatchRelayControlFrame(decoded.frame);
    } else if (decoded.kind === "outer") {
      // Owner attachment may require an async peers.json lookup. Complete it
      // before typed fanout so a newly created SecurePeerChannel receives the
      // triggering protected frame; no plaintext shortcut is permitted.
      for (const handler of outerMessageHandlers) {
        if (await handler(decoded, isCurrent) === true) consumed = true;
      }
    }
    // A consumed pair_request stays on the plaintext handshake path and must
    // not be re-published into the newly established SecurePeerChannel.
    if (!consumed) publishRelayIngress(source, decoded);
  }

  function createPeerChannel(input: RelayPeerChannelInput): RelayPeerChannel {
    const current = relay;
    if (!current) throw new Error("relay transport is not connected");
    if (!input.peerRecord) {
      return new PlainPeerChannel(
        current,
        input.peerId,
        (message) => { void input.onMessage(message); },
      );
    }

    const keys = decodePeerChannelKeys(input.peerRecord.channel_key);
    const sendSeq = parsePeerChannelSequence(input.peerRecord.send_seq);
    const recvSeq = parsePeerChannelSequence(input.peerRecord.recv_seq);
    if (!keys || sendSeq === null || recvSeq === null || !input.peerRecord.channel_key) {
      throw new Error("established owner has invalid protected-channel state");
    }
    const channelKey = input.peerRecord.channel_key;
    return new SecurePeerChannel(
      current,
      input.peerId,
      (message) => { void input.onMessage(message); },
      {
        keys,
        recvSeq,
        reserveSendSeq: () => reserveSendSeq(input.peerId, channelKey),
        compareAndAdvanceRecvSeq: (seq) => compareAndAdvanceRecvSeq(input.peerId, channelKey, seq),
        onDisconnect: () => input.onDisconnect(input.peerId),
      },
    );
  }

  function subscribePresence(peers: readonly string[]): void {
    relay?.sendControl({ type: "subscribe_presence", peers: [...peers] });
  }

  function bridgeKeyId(nextKeypair: Ed25519Keypair): string {
    return Buffer.from(nextKeypair.publicKey).toString("base64");
  }

  function sameBridgeAttachment(
    attachment: BridgeAttachment,
    nextRelay: RelayClient,
    nextRelayUrl: string,
    nextMeshNode: BridgeAttachment["meshNode"],
    nextKeyId: string,
  ): boolean {
    return attachment.relay === nextRelay &&
      attachment.relayUrl === nextRelayUrl &&
      attachment.meshNode === nextMeshNode &&
      attachment.keyId === nextKeyId;
  }

  function bridgeAttachmentIsCurrent(
    epoch: number,
    currentRelay: RelayClient,
    currentRelayUrl: string,
    meshNode: BridgeAttachment["meshNode"],
    keyId: string,
  ): boolean {
    const attachment = activeBridge;
    return !!attachment &&
      attachment.epoch === epoch &&
      sameBridgeAttachment(attachment, currentRelay, currentRelayUrl, meshNode, keyId) &&
      relay === currentRelay &&
      relayUrl === currentRelayUrl &&
      !stopping &&
      !isDisposed?.();
  }

  async function attachCrossPcBridge(input: CrossPcBridgeInput): Promise<void> {
    crossPcBridgeInput = input;
    const currentRelay = relay;
    const currentRelayUrl = relayUrl;
    const meshNode = input.meshNode();
    const currentKeypair = input.keypair();
    if (!meshNode || !currentRelay || !currentRelayUrl || !currentKeypair) return;

    const keyId = bridgeKeyId(currentKeypair);
    if (activeBridge && sameBridgeAttachment(activeBridge, currentRelay, currentRelayUrl, meshNode, keyId)) {
      await activeBridge.pending;
      return;
    }

    if (activeBridge) {
      try { activeBridge.meshNode.detachBridge(); } catch { /* best-effort stale bridge cleanup */ }
      activeBridge = null;
    }

    const epoch = ++bridgeEpoch;
    const isCurrent = () => bridgeAttachmentIsCurrent(epoch, currentRelay, currentRelayUrl, meshNode, keyId);
    const attachPromise = Promise.resolve().then(async () => {
      try {
        await meshNode.attachBridge({
          relay: currentRelay,
          relayUrl: currentRelayUrl,
          keypair: currentKeypair,
          isCurrent,
        });
      } catch {
        // Best-effort: local UDS mesh and app pairing continue without the
        // cross-PC relay bridge.
        if (isCurrent()) activeBridge = null;
        return;
      }
      if (!isCurrent()) {
        try { meshNode.detachBridge(); } catch { /* best-effort stale bridge cleanup */ }
        if (activeBridge && activeBridge.epoch === epoch) activeBridge = null;
      }
    });

    activeBridge = {
      relay: currentRelay,
      relayUrl: currentRelayUrl,
      meshNode,
      keyId,
      epoch,
      pending: attachPromise,
    };
    await attachPromise;
  }

  function detachCrossPcBridge(): void {
    bridgeEpoch += 1;
    const attachment = activeBridge;
    activeBridge = null;
    if (attachment) {
      try { attachment.meshNode.detachBridge(); } catch { /* best-effort bridge cleanup */ }
      return;
    }
    crossPcBridgeInput?.meshNode()?.detachBridge();
  }

  return {
    status,
    start,
    stop,
    sendRoomMeta,
    onOuterMessage,
    createPeerChannel,
    subscribePresence,
    onControlFrame,
    attachCrossPcBridge,
    detachCrossPcBridge,
    emitRelayState,
    hasPendingReconnect: () => reconnectTimer !== null,
    currentRelayUrl: () => relayUrl,
  };
}

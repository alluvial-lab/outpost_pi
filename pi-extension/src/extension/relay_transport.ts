import type { ByeReason, ThinkingLevel } from "../protocol/types.js";
import type { RelayControlFrame } from "../protocol/generated/protocol.generated.js";
import type { Ed25519Keypair } from "../pairing/crypto.js";
import {
  REACHABILITY_RELAY_LIVENESS_CHECK_MS,
  REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS,
  reachabilityBackoffMs,
} from "../reachability/reachability_contract.js";
import type { RelayClient, RoomMeta } from "../transport/relay_client.js";
import { PlainPeerChannel } from "../transport/peer_channel.js";
import type {
  CrossPcBridgeInput,
  RelayPeerChannel,
  RelayPeerChannelInput,
  RelayStartInput,
  RelayStartResult,
  RelayTransportPort,
} from "./ports.js";
import type { RelayConnectivity } from "./types.js";

export interface RelayStateSnapshot {
  status: RelayConnectivity;
  connected: boolean;
  relayUrl?: string;
  room?: string;
}

export interface RelayTransportStartInput extends RelayStartInput {
  isDisposed?: () => boolean;
  onUnexpectedClose?: () => void;
  onConnected?: (relay: RelayClient) => void | Promise<void>;
}

export class RelayStartAbortedError extends Error {
  constructor() {
    super("relay start aborted");
    this.name = "RelayStartAbortedError";
  }
}

export interface RelayTransportDeps {
  createRelay(url: string, keypair: Ed25519Keypair): RelayClient;
  toWebSocketUrl(url: string): string;
  backoffMs(attempt: number): number;
  now(): number;
  setTimer(cb: () => void, delayMs: number): ReturnType<typeof setTimeout>;
  clearTimer(timer: ReturnType<typeof setTimeout>): void;
  emitRelayState(snapshot: RelayStateSnapshot): void;
}

export interface RelayTransportAdapter extends Omit<RelayTransportPort, "start" | "createPeerChannel"> {
  start(input: RelayTransportStartInput): Promise<RelayStartResult>;
  createPeerChannel(input: RelayPeerChannelInput): RelayPeerChannel;
  onControlFrame(handler: (frame: RelayControlFrame) => void | Promise<void>): () => void;
  emitRelayState(force?: boolean): void;
  hasPendingReconnect(): boolean;
  currentRelayUrl(): string | null;
  /**
   * @internal Temporary owner-channel bridge while legacy call sites still need
   * direct access to the live RelayClient. Remove when owner ingress is fully
   * routed through RelayTransportPort.
   */
  currentRelayForOwnerChannels(): RelayClient | null;
}

export const RELAY_TRANSPORT_REACHABILITY = {
  backoffMs: reachabilityBackoffMs,
  livenessTimeoutMs: REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS,
  livenessCheckMs: REACHABILITY_RELAY_LIVENESS_CHECK_MS,
} as const;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

export function decodeRelayControlFrame(line: string): RelayControlFrame | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(line) as unknown;
  } catch {
    return null;
  }
  if (!isRecord(parsed) || typeof parsed.type !== "string") return null;

  if (parsed.type === "peer_online") {
    return typeof parsed.peer === "string" && parsed.peer.length > 0
      ? { type: "peer_online", peer: parsed.peer }
      : null;
  }

  if (parsed.type === "peer_offline") {
    return typeof parsed.peer === "string" && parsed.peer.length > 0 && typeof parsed.since_ts === "number"
      ? { type: "peer_offline", peer: parsed.peer, since_ts: parsed.since_ts }
      : null;
  }

  if (parsed.type === "presence") {
    // Fail fast at the boundary: if any state entry is malformed (missing
    // non-empty `peer`, non-boolean `online`, or a non-number `since_ts`
    // that isn't null/absent), reject the WHOLE frame rather than silently
    // dropping the bad entry. Silently dropping could mask a relay bug or a
    // missed offline/online transition. (Adversarial review I1.)
    if (!Array.isArray(parsed.states)) return null;
    const states: Array<{ peer: string; online: boolean; since_ts?: number | null }> = [];
    for (const state of parsed.states) {
      if (
        !isRecord(state) ||
        typeof state.peer !== "string" ||
        state.peer.length === 0 ||
        typeof state.online !== "boolean" ||
        (state.since_ts !== undefined && state.since_ts !== null && typeof state.since_ts !== "number")
      ) {
        return null;
      }
      states.push({
        peer: state.peer,
        online: state.online,
        ...(state.since_ts === undefined ? {} : { since_ts: state.since_ts as number | null }),
      });
    }
    return { type: "presence", states };
  }

  return null;
}

export function createRelayTransportPort(deps: RelayTransportDeps): RelayTransportAdapter {
  const backoffMs = deps.backoffMs ?? reachabilityBackoffMs;
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
  const outerMessageHandlers = new Set<(line: string) => void | Promise<void>>();
  const controlFrameHandlers = new Set<(frame: RelayControlFrame) => void | Promise<void>>();
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

  function bindRelay(next: RelayClient): void {
    next.on("message", dispatchRelayMessage);
    next.on("close", onRelayClose);
  }

  function unbindRelay(current: RelayClient): void {
    current.off("close", onRelayClose);
    current.off("message", dispatchRelayMessage);
  }

  function clearReconnectTimer(): void {
    if (reconnectTimer === null) return;
    deps.clearTimer(reconnectTimer);
    reconnectTimer = null;
  }

  function onRelayClose(): void {
    if (stopping || !relayUrl) return;
    detachCrossPcBridge();
    if (relay) {
      unbindRelay(relay);
      relay = null;
    }
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
    return { relay: nextRelay, roomId: input.roomId };
  }

  function stop(_reason?: ByeReason): void {
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
    relay?.sendControl({ type: "room_meta_update", room_id: roomId, meta: patch });
  }

  function onOuterMessage(handler: (line: string) => void | Promise<void>): () => void {
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

  function dispatchRelayMessage(line: string): void {
    const frame = decodeRelayControlFrame(line);
    if (frame) {
      for (const handler of controlFrameHandlers) {
        void handler(frame);
      }
    }
    for (const handler of outerMessageHandlers) {
      void handler(line);
    }
  }

  function createPeerChannel(input: RelayPeerChannelInput): RelayPeerChannel {
    const current = relay;
    if (!current) throw new Error("relay transport is not connected");
    return new PlainPeerChannel(
      current,
      input.peerId,
      (message) => { void input.onMessage(message); },
      () => input.onDisconnect(input.peerId),
    );
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
    onControlFrame,
    attachCrossPcBridge,
    detachCrossPcBridge,
    emitRelayState,
    hasPendingReconnect: () => reconnectTimer !== null,
    currentRelayUrl: () => relayUrl,
    currentRelayForOwnerChannels: () => relay,
  };
}

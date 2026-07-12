import type {
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import type {
  ByeReason,
  ClientMessage,
  ServerMessage,
  ThinkingLevel,
} from "../protocol/types.js";
import type { RelayClient, RoomMeta } from "../transport/relay_client.js";
import type { PeerChannel } from "../transport/peer_channel.js";
import type { Ed25519Keypair } from "../pairing/crypto.js";
import type { RelayConnectivity } from "./types.js";

export interface RuntimeEpoch {
  readonly id: number;
  readonly disposed: boolean;
  isCurrent(): boolean;
  dispose(): void;
}

export interface RuntimeUiPort {
  notify(message: string, type?: "info" | "warning" | "error"): void;
  setStatus(key: string, value: string | undefined): void;
  setTitle(title: string): void;
}

export interface RelayStartInput {
  relayUrl: string;
  keypair?: Ed25519Keypair;
  roomId?: string;
  roomMeta?: RoomMeta;
}

export interface RelayStartResult {
  relay: RelayClient;
  roomId?: string;
}

export interface CrossPcBridgeMeshNode {
  attachBridge(opts: {
    relay: RelayClient;
    relayUrl: string;
    keypair?: Ed25519Keypair;
    isCurrent?: () => boolean;
  }): Promise<void>;
  detachBridge(): void;
}

export interface CrossPcBridgeInput {
  meshNode(): CrossPcBridgeMeshNode | null;
  keypair(): Ed25519Keypair | null;
}

export interface RelayPeerChannel extends PeerChannel {
  detach(): void;
}

export interface RelayPeerChannelInput {
  peerId: string;
  roomId?: string;
  onMessage(message: ClientMessage): void | Promise<void>;
  onDisconnect(peerId: string): void;
}

export interface RelayTransportPort {
  status(): RelayConnectivity;
  start(input: RelayStartInput): Promise<RelayStartResult>;
  stop(reason?: ByeReason): void;
  sendRoomMeta(patch: Partial<RoomMeta> & { working?: boolean; thinking?: ThinkingLevel }): void;
  onOuterMessage(handler: (line: string) => void | Promise<void>): () => void;
  createPeerChannel?(input: RelayPeerChannelInput): RelayPeerChannel;
  attachCrossPcBridge(input: CrossPcBridgeInput): Promise<void>;
  detachCrossPcBridge(): void;
}

export interface AttachOwnerInput {
  relay: RelayClient;
  peerId: string;
  roomId?: string;
  onMessage(message: ClientMessage, sender: PeerChannel): void | Promise<void>;
  onDisconnect?(peerId: string): void;
}

export interface OwnerMultiplexerPort {
  activeCount(): number;
  attach(input: AttachOwnerInput): PeerChannel;
  detach(peerId: string, reason?: ByeReason): void;
  broadcast(message: ServerMessage): void;
  routeFrom(sender: PeerChannel, message: ClientMessage): void | Promise<void>;
  lateAttachTargets(): readonly PeerChannel[];
}

export interface WakeAgentResult {
  ok: boolean;
  detail?: string;
  /** True when the failure is recoverable: a stale session ctx after a
   *  replacement/reload, or the null-`messageApi` window immediately after.
   *  Such a message was not delivered to THIS pi's agent, but the phone should
   *  NOT see a permanent `internal_error` — either another pi handled it
   *  (cross-process fanout) or the next `session_start` rebinds a working api
   *  and the phone retries. Real delivery failures leave this false so they
   *  still surface. */
  recoverable?: boolean;
}

export interface SdkSessionProjectionPort {
  /** Set the room id for delivery-log correlation. Called when `_myRoomId` is
   *  bound (the projection is constructed before the room is known). */
  setRoomId(roomId: string | null): void;
  bindApi(pi: ExtensionAPI): void;
  bindCommandContext(ctx: ExtensionCommandContext): void;
  bindSessionContext(ctx: ExtensionContext): void;
  clearStaleContexts(reason?: "startup" | "reload" | "new" | "resume" | "fork" | "quit"): void;
  sendPiMessage(...args: Parameters<ExtensionAPI["sendMessage"]>): boolean;
  wakeAgent(...args: Parameters<ExtensionAPI["sendUserMessage"]>): Promise<WakeAgentResult>;
  publishWorking(working: boolean): void;
  handleClientMessage(sender: PeerChannel, message: ClientMessage): void | Promise<void>;
  /** Delivery-path debug: session lifecycle transition (the precursor that
   * opens the null window). `reason` is the SDK event reason
   * (startup/reload/new/resume/fork/quit). Optional — no-op when the debug
   * log is disabled. */
  onSessionLifecycle?(reason: string, sessionIdTail: string): void;
}

export interface OutpostPiRuntime {
  readonly epoch: RuntimeEpoch;
  readonly ports: OutpostPiRuntimePorts;
}

export interface CommandSurfacePort {
  register(pi: ExtensionAPI, runtime: OutpostPiRuntime): void;
  ensureStarted?(ctx: ExtensionContext): void | Promise<void>;
  prepareSessionShutdown?(): void;
  closeMesh?(): Promise<void>;
}

export interface OutpostPiRuntimePorts {
  relay: RelayTransportPort;
  owners: OwnerMultiplexerPort;
  session: SdkSessionProjectionPort;
  commands: CommandSurfacePort;
}

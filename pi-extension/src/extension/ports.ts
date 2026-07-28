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
import type { DecodedRelayIngress } from "../protocol/relay_ingress.js";
import type { RelayClient, RoomMeta } from "../transport/relay_client.js";
import type { PeerChannel } from "../transport/peer_channel.js";
import type { Ed25519Keypair } from "../pairing/crypto.js";
import type { PeerRecord } from "../pairing/storage.js";
import type { RelayConnectivity } from "./types.js";

/** Guard asynchronous runtime work so a disposed session epoch cannot publish or reconnect. */
export interface RuntimeEpoch {
  readonly id: number;
  readonly disposed: boolean;
  isCurrent(): boolean;
  dispose(): void;
}

/** Provide the minimal UI effects available to a lifecycle-owned runtime. */
export interface RuntimeUiPort {
  notify(message: string, type?: "info" | "warning" | "error"): void;
  setStatus(key: string, value: string | undefined): void;
  setTitle(title: string): void;
}

/** Provide the authenticated room context required to open a relay transport. */
export interface RelayStartInput {
  relayUrl: string;
  keypair?: Ed25519Keypair;
  roomId?: string;
  roomMeta?: RoomMeta;
}

/** Return the effective room after transport startup. */
export interface RelayStartResult {
  roomId?: string;
}

/** Describe the mesh-side bridge lifecycle controlled by the relay transport. */
export interface CrossPcBridgeMeshNode {
  attachBridge(opts: {
    relay: RelayClient;
    relayUrl: string;
    keypair?: Ed25519Keypair;
    isCurrent?: () => boolean;
  }): Promise<void>;
  detachBridge(): void;
}

/** Lazily resolve the live mesh and identity required to attach cross-PC forwarding. */
export interface CrossPcBridgeInput {
  meshNode(): CrossPcBridgeMeshNode | null;
  keypair(): Ed25519Keypair | null;
}

/** Expose a relay-backed owner channel whose listeners can be explicitly detached. */
export interface RelayPeerChannel extends PeerChannel {
  detach(): void;
}

/** Define routing callbacks and peer identity for a newly created relay owner channel. */
export interface RelayPeerChannelInput {
  peerId: string;
  roomId?: string;
  /** Present only for established owners; absence selects the pre-key plaintext adapter. */
  peerRecord?: PeerRecord;
  onMessage(message: ClientMessage): void | Promise<void>;
  onDisconnect(peerId: string): void;
}

/** Own relay connection, reconnect, room metadata, and cross-PC bridge lifecycle for one runtime. */
export interface RelayTransportPort {
  status(): RelayConnectivity;
  start(input: RelayStartInput): Promise<RelayStartResult>;
  stop(reason?: ByeReason): void;
  sendRoomMeta(patch: Partial<RoomMeta> & { working?: boolean; thinking?: ThinkingLevel }): void;
  onOuterMessage(
    handler: (
      ingress: Extract<DecodedRelayIngress, { kind: "outer" }>,
      isCurrent: () => boolean,
    ) => boolean | void | Promise<boolean | void>,
  ): () => void;
  createPeerChannel(input: RelayPeerChannelInput): RelayPeerChannel;
  subscribePresence(peers: readonly string[]): void;
  attachCrossPcBridge(input: CrossPcBridgeInput): Promise<void>;
  detachCrossPcBridge(): void;
}

/** Provide the routing callbacks required to attach one app owner. */
export interface AttachOwnerInput {
  peerId: string;
  roomId?: string;
  onMessage(message: ClientMessage, sender: PeerChannel): void | Promise<void>;
  onDisconnect?(peerId: string): void;
}

/** Manage per-owner channels while preserving broadcast, routing, and teardown ownership. */
export interface OwnerMultiplexerPort {
  activeCount(): number;
  attach(input: AttachOwnerInput): PeerChannel;
  detach(peerId: string, reason?: ByeReason): Promise<void>;
  broadcast(message: ServerMessage): void;
  completeOfflineTurn(): void;
  routeFrom(sender: PeerChannel, message: ClientMessage): void | Promise<void>;
  lateAttachTargets(): readonly PeerChannel[];
}

/** Distinguish delivered, retryable lifecycle-window, and permanent agent wake outcomes. */
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

/** Project Pi SDK session effects while owning stale-context invalidation across replacements. */
export interface SdkSessionProjectionPort {
  bindApi(pi: ExtensionAPI): void;
  bindCommandContext(ctx: ExtensionCommandContext): void;
  bindSessionContext(ctx: ExtensionContext): void;
  clearStaleContexts(reason?: "startup" | "reload" | "new" | "resume" | "fork" | "quit"): void;
  sendPiMessage(...args: Parameters<ExtensionAPI["sendMessage"]>): boolean;
  wakeAgent(...args: Parameters<ExtensionAPI["sendUserMessage"]>): Promise<WakeAgentResult>;
  publishWorking(working: boolean): void;
  /** Converge the turn projection to idle and publish `working=false` while
   *  the relay is still connected. Called at session shutdown so a replacement
   *  or quit during an active turn does not leave the app's working indicator
   *  stuck true (the old runner is invalidated and its terminal `agent_end`/
   *  `turn_end` events are dropped, so the reducer-owned `working=true` would
   *  otherwise never transition or publish). */
  resetTurnSnapshot(): void;
  handleClientMessage(sender: PeerChannel, message: ClientMessage): void | Promise<void>;
  /** Delivery-path debug: session lifecycle transition (the precursor that
   * opens the null window). `reason` is the SDK event reason
   * (startup/reload/new/resume/fork/quit). Optional — no-op when the debug
   * log is disabled. */
  onSessionLifecycle?(reason: string, sessionIdTail: string): void;
}

/** Represent the composed runtime epoch and port graph visible to command registration. */
export interface OutpostPiRuntime {
  readonly epoch: RuntimeEpoch;
  readonly ports: OutpostPiRuntimePorts;
}

/** Register command adapters and coordinate their session-start and shutdown hooks. */
export interface CommandSurfacePort {
  register(pi: ExtensionAPI, runtime: OutpostPiRuntime): void;
  /** Synchronously trigger startup; implementations own and observe background failures. */
  ensureStarted?(ctx: ExtensionContext): void;
  prepareSessionShutdown?(): void;
  closeMesh?(): Promise<void>;
}

/** Group the lifecycle-owned adapter ports required to compose an extension runtime. */
export interface OutpostPiRuntimePorts {
  relay: RelayTransportPort;
  owners: OwnerMultiplexerPort;
  session: SdkSessionProjectionPort;
  commands: CommandSurfacePort;
}

#!/usr/bin/env node
/**
 * pi-extension — outpost-pi slash commands + AgentBridge wiring
 *
 * Exported as ExtensionFactory (default export) to be loaded by Pi SDK:
 *   pi -e $(pwd)/dist/index.js
 *
 * State machine:  idle → started → paired
 *   /outpost-pi start   connects to relay (idle → started)
 *   /outpost-pi pair    shows QR for new peers (started, async → paired via auto-listener)
 *   /outpost-pi stop    closes everything (any → idle)
 *
 * Pairing:
 *   The app proves knowledge of the QR token without sending it, then exchanges
 *   Owner/Pi-signed ephemeral X25519 shares over the plaintext pre-key channel.
 *   The Pi persists directional owner-channel keys before returning `pair_ok`.
 *
 * Known-peer reconnection:
 *   When a protected frame arrives from an Owner present in peers.json, the
 *   auto-listener attaches a SecurePeerChannel and routes only AEAD-authenticated
 *   messages. PlainPeerChannel is restricted to pair_request/pair_ok exchange.
 *
 * Architecture note — why we don't use AgentBridge directly here:
 *   AgentBridge.beforeToolCallHook is designed to be passed to createAgentSession().
 *   Inside an extension Pi already owns the AgentSession, so we can't re-bind
 *   beforeToolCall after the fact. The equivalent is pi.on("tool_call", …) which
 *   fires BEFORE execution and supports { block: true }.
 *   AgentBridge (src/session/agent_bridge.ts) remains the tested, mockable unit
 *   for integration tests.
 */

import { randomUUID } from "node:crypto";
import {
  SettingsManager,
  type ExtensionAPI,
  type ExtensionCommandContext,
  type ExtensionContext,
  type ExtensionFactory,
} from "@earendil-works/pi-coding-agent";
import { qrSession } from "./pairing/qr.js";
import { deviceIdFromPublicKey, type Ed25519Keypair } from "./pairing/crypto.js";
import {
  addPeer,
  getOrCreateEd25519Keypair,
  KeyringUnavailableError,
  PairedIdentityMissingError,
  listPeers,
  removePeer,
} from "./pairing/storage.js";
import type {
  ClientMessage,
  ServerMessage,
  ThinkingLevel,
} from "./protocol/types.js";
import type { RelayControlFrame } from "./protocol/generated/protocol.generated.js";
import type { DecodedRelayIngress } from "./protocol/relay_ingress.js";
import type { TranscriptEvent } from "./session/transcript_event.js";
import type { TranscriptRecordResult } from "./session/transcript_event_log.js";
import {
  deterministicTranscriptEventId,
  stringifyToolResult,
  type SdkTranscriptMessage,
} from "./session/transcript_projection.js";
import { RelayClient, RoomAlreadyOpenError } from "./transport/relay_client.js";
import { appendOwnerChannelAudit, type PeerChannel, type PlainPeerChannel } from "./transport/peer_channel.js";
import { OwnerMultiplexer } from "./extension/owner_multiplexer.js";
import {
  createOutpostPiTestHarness,
  type OwnerMultiplexerTestHarness,
  type OutpostPiTestHarness,
} from "./extension/testing.js";
import { createCommandSurface } from "./extension/command_surface.js";
import { registerOutpostPiCommands, type OutpostPiCommandSpec } from "./extension/command_surface/commands.js";
import { LocalMeshCommands } from "./extension/command_surface/local_mesh_commands.js";
import { DaemonCommands } from "./extension/command_surface/daemon_commands.js";
import { CronCommands } from "./extension/command_surface/cron_commands.js";
import { PairingCommands } from "./extension/command_surface/pairing_commands.js";
import { PairingCoordinator } from "./extension/command_surface/pairing_coordinator.js";
import { RelayCommands } from "./extension/command_surface/relay_commands.js";
import { ServiceCommands } from "./extension/command_surface/service_commands.js";
import { restartSupervisor } from "./extension/command_surface/supervisor_restart.js";
import { createStandaloneCliDeps, isDirectRun, launchClaudeCli, runStandaloneOutpostPiCli } from "./extension/command_surface/standalone_cli.js";
import { probeListPeers } from "./extension/probe_list_peers.js";
export { probeListPeers } from "./extension/probe_list_peers.js";
export { restartSupervisorCommand as _restartSupervisorCommand } from "./extension/command_surface/supervisor_restart.js";
export type { RestartStep } from "./extension/command_surface/supervisor_restart.js";
import { createOutpostPiExtensionRuntime } from "./extension/composition_root.js";
import { FreshSessionShutdownCoordinator } from "./extension/fresh_session_shutdown.js";
import { getOutpostPiRuntimeCoordinator } from "./extension/runtime_coordinator.js";
import type {
  CommandSurfacePort,
  OutpostPiRuntime,
  OutpostPiRuntimePorts,
  WakeAgentResult,
} from "./extension/ports.js";
import { SdkSessionProjection } from "./session/sdk_session_projection.js";
import { createDeliveryDebugLog, idTail } from "./session/delivery_debug_log.js";
import type { DeliveryDebugLog } from "./session/delivery_debug_log.js";
import { roomIdFor } from "./rooms.js";
import { registerAgentTools } from "./session/tools.js";
import { formatPeerInventory } from "./session/peer_inventory.js";
import { MeshNode } from "./session/mesh_node.js";
import { reachabilityBackoffMs } from "./reachability/reachability_contract.js";
import {
  createRelayTransportPort,
  RelayStartAbortedError,
  type RelayStateSnapshot,
} from "./extension/relay_transport.js";
import { validateClientSession } from "./session/session_gate.js";
import { subagentGate } from "./session/subagent_gate.js";
import type { TurnEvent, TurnProjection } from "./session/turn_state.js";
import {
  handleSessionCompact,
  handleSessionNew,
  handleModelSet,
  handleThinkingSet,
  handleListModels,
  type ActionCtx,
} from "./actions/handlers.js";
import { ensureModelRegistry } from "./actions/registry.js";
import { CaptureUploadHandler } from "./actions/capture_upload_handler.js";
import {
  ensureGlobalDirs,
  LOCAL_SESSION_NAME,
  sessionSockPath,
  skillsDir,
} from "./session/global_config.js";
import { EXIT_FRESH_SESSION } from "./daemon/rpc_child.js";
import {
  defaultAgentName,
  loadLocalConfig,
} from "./session/local_config.js";
import { updateFooter, type FooterState } from "./ui/footer.js";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { mkdirSync, copyFileSync, existsSync, unlinkSync, readFileSync, writeFileSync, lstatSync, readdirSync } from "node:fs";
import { homedir, hostname } from "node:os";
import {
  resolveRelayUrl,
  saveConfig,
  toWebSocketUrl,
} from "./config.js";

// ── State machine ─────────────────────────────────────────────────────────────
//
// Pre-2026-05-23: `idle` → `started` → `paired` (one owner at a time, gate-kept
// by `_appPeerId`/`_peerChannel` singletons). The transition to `paired` was
// what unblocked the app from sending application messages.
//
// Now: `idle` → `started`. The `paired` state is a derived metric
// (`OwnerMultiplexer.activeCount() > 0`) — N owners can be connected at once,
// each with its own `SecurePeerChannel` owned by the multiplexer. Plan/24 W2D
// ("multi-channel broadcast"): pairing a second device no longer disconnects
// the first, and every connected owner receives the same agent stream in parallel.

/** Relay runtime lifecycle state.
 * - `idle` — relay transport not started (no WS, no pairing channel).
 * - `started` — relay transport running; the extension connects/reconnects
 *   to the relay URL and routes app↔agent traffic.
 *
 * Drives the footer slot and the `/outpost-pi status` relay line. Mutated
 * only by `_startRelay`/`_stopRelay`; read via `_state`. */
export type RemoteState = "idle" | "started";

let _state: RemoteState = "idle";

/** Relay connectivity as seen by an RPC client (Cockpit). Derived by the relay
 *  transport adapter: "disconnected" = relay off (idle); "connected" = live
 *  WS; "reconnecting" = was on, WS dropped, retrying. Surfaced via the
 *  `outpost-pi:relay-state` custom message (see `_emitRelayState`). */
export type RelayConnectivity = "connected" | "reconnecting" | "disconnected";

/** Sentinel prefix for a transparent control message an RPC client sends on the
 *  `prompt` channel (stdin). The `input` hook intercepts it, runs the action,
 *  and swallows it (`action:"handled"`) so it never becomes an LLM turn or a
 *  transcript entry. Starts with NUL so it can't collide with real user input
 *  and doesn't begin with "/" (which would route to the command parser). */
export const CTRL_PREFIX = "\x00outpost-pi-ctrl:";

const STRUCTURED_CONTROL_TYPE = "outpost_pi_control";
const STRUCTURED_CONTROL_COMMANDS = {
  relay_on: "relay:on",
  relay_off: "relay:off",
  relay_toggle: "relay:toggle",
  relay_status: "relay:status",
} as const;

type StructuredControlCommand = keyof typeof STRUCTURED_CONTROL_COMMANDS | "rename";
type ParsedControlFrame = { command: string };

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function structuredControlToCommand(payload: unknown): ParsedControlFrame | null {
  if (!isRecord(payload)) return null;
  if (payload["type"] !== STRUCTURED_CONTROL_TYPE) return null;

  const command = payload["command"];
  if (typeof command !== "string") return null;
  if (command === "rename") {
    const name = payload["name"];
    if (typeof name !== "string" || name.trim().length === 0) return null;
    return { command: `rename:${name}` };
  }

  if (!Object.prototype.hasOwnProperty.call(STRUCTURED_CONTROL_COMMANDS, command)) return null;
  return { command: STRUCTURED_CONTROL_COMMANDS[command as Exclude<StructuredControlCommand, "rename">] };
}

export function _parseControlFrame(text: string): ParsedControlFrame | null {
  try {
    const parsed = structuredControlToCommand(JSON.parse(text));
    if (parsed) return parsed;
  } catch {
    // Malformed JSON is ordinary user input unless it also uses the legacy prefix.
  }

  if (text.startsWith(CTRL_PREFIX)) {
    return { command: text.slice(CTRL_PREFIX.length).trim() };
  }
  return null;
}

let _myRoomId: string | null = null;   // this Pi's room id (derived from cwd)

const _relayTransport = createRelayTransportPort({
  createRelay: (url, keypair) => new RelayClient(url, keypair, deviceIdFromPublicKey(keypair.publicKey)),
  toWebSocketUrl,
  backoffMs: reachabilityBackoffMs,
  now: () => Date.now(),
  setTimer: (cb, delayMs) => setTimeout(cb, delayMs),
  clearTimer: (timer) => clearTimeout(timer),
  emitRelayState: (snapshot) => _sendRelayStateSnapshot(snapshot),
});

const _owners: OwnerMultiplexer = new OwnerMultiplexer({
  createChannel: (input) => _relayTransport.createPeerChannel({
    peerId: input.peerId,
    roomId: input.roomId ?? _myRoomId ?? undefined,
    peerRecord: input.peerRecord,
    onMessage: input.onMessage,
    onDisconnect: input.onDisconnect,
  }),
  refreshFooter: () => _refreshFooter(),
  listPeers: () => listPeers(),
  findKnownPeer: async (peerId) => {
    const peers = await listPeers();
    return peers.find((p) => p.remote_epk === peerId) ?? null;
  },
  findPairTokenById: (tokenId) => qrSession.findTokenById(tokenId),
  consumePairToken: (token) => qrSession.consumeToken(token),
  addPeer: (record) => addPeer(record),
  currentIdentity: () => _pairingCoordinator.currentKeypair(),
  auditDrop: (peerId, reason) => { void appendOwnerChannelAudit(peerId, reason); },
  onPeerPersisted: () => { void _owners.refreshPairingsCache(); },
  currentPairingSession: () => {
    const cwd = _currentCwd();
    const sessionName = _displayName(cwd);
    return {
      sessionName,
      sessionStartedAt: _sdkSessionProjection.sessionStartedAtOrNow(),
      sessionId: _currentRemoteSessionId(_lastEventCtx ?? _lastCtx),
      roomId: _myRoomId ?? roomIdFor(cwd, sessionName),
      harness: _HARNESS,
      hostname: _HOSTNAME,
    };
  },
  makeUnknownPeerError: () => _withCurrentSession({
    type: "error",
    code: "unknown_peer",
    message: "Peer not paired — re-scan QR",
  }),
  onOwnerAttached: ({ peerId, peerName, activeCount }) => {
    _sdkSessionProjection.recordOwnerAttached(peerId);
    _syncOwnerPresenceSubscription();
    _notify(
      `[outpost-pi] Owner attached: peer=${peerId.slice(0, 8)}, name=${peerName} ` +
      `(${activeCount} active)`,
      "info",
    );
  },
  onOwnerPaired: ({ peerId, peerName, pairedAt }) => {
    _sendPiMessage({
      customType: "outpost-pi:paired",
      content: `Paired with ${peerName}`,
      details: { name: peerName, peerId, pairedAt },
      display: false,
    }, undefined, "paired");
  },
  onOwnerChannelDetached: ({ peerId, channel }) => {
    _captureUploads?.detachChannel(peerId, channel);
  },
  onFanoutPresenceChanged: ({ peerShortId, state, sinceTs }) => {
    // Operational telemetry only — do NOT emit anything to the TUI or the
    // agent's message context. A prior version called `_sendPiMessage` (which
    // injected the fan-out text into the agent's conversation as a `custom`
    // message — the agent then responded to it) AND `_notify` (which spammed
    // the TUI footer with a Warning per flap). `display: false` only
    // suppresses the TUI bubble render; it does NOT keep the message out of
    // the agent's context. `console.warn` is ALSO unsuitable: pi surfaces
    // extension `console.warn` to the TUI as a notification (runner.js:297),
    // so the spam persisted. Fan-out suspend/resume fires on every mobile
    // connection flap (normal mobile behavior), so any TUI output is too
    // noisy. Silent is correct — the suspend/resume is a purely internal
    // transport state; the app rehydrates via session_sync on reconnect, and
    // the operator does not need to see every flap. If diagnostics are ever
    // needed, they should go to a debug log file, not the TUI. See
    // `story-extension-suspend-fanout-on-peer-offline` (post-deploy fix).
    void peerShortId; void state; void sinceTs;
  },
});

const ownerHarness: OwnerMultiplexerTestHarness = {
  activeOwnerCount: () => _owners.activeCount(),
  hasOwner: (peerId) => _owners.has(peerId),
  disconnectOwner: (peerId) => _disconnectOwnerForRuntime(peerId),
  fallbackRoute: (message, ctx) => {
    const fallback = _owners.entries().at(-1)?.channel;
    if (!fallback) return;
    _routeClientMessageFrom(fallback as PlainPeerChannel, message, ctx);
  },
};

let _stopOwnerIngress: (() => void) | null = null;
let _stopOwnerControl: (() => void) | null = null;

function _ensureOwnerIngressListener(): void {
  if (!_stopOwnerIngress) {
    _stopOwnerIngress = _relayTransport.onOuterMessage((ingress, isCurrent, signal) =>
      _handleOwnerOuterFrame(ingress, isCurrent, signal)
    );
  }
  if (!_stopOwnerControl) {
    _stopOwnerControl = _relayTransport.onControlFrame((frame) => {
      _handleRelayControlFrame(frame);
    });
  }
}

function _stopOwnerIngressListener(): void {
  _stopOwnerIngress?.();
  _stopOwnerControl?.();
  _stopOwnerIngress = null;
  _stopOwnerControl = null;
}

function _handleRelayControlFrame(frame: RelayControlFrame): void {
  if (frame.type === "peer_offline") {
    _owners.markPeerOffline(frame.peer, frame.since_ts);
    return;
  }
  if (frame.type === "peer_online") {
    _owners.markPeerOnline(frame.peer);
    return;
  }
  if (frame.type === "presence") {
    for (const state of frame.states) {
      if (state.online) _owners.markPeerOnline(state.peer);
      else _owners.markPeerOffline(state.peer, state.since_ts ?? undefined);
    }
  }
}

async function _handleOwnerOuterFrame(
  ingress: Extract<DecodedRelayIngress, { kind: "outer" }>,
  connectionIsCurrent: () => boolean,
  signal: AbortSignal,
): Promise<boolean> {
  if (signal.aborted) return false;
  const consumed = await _owners.handleOuterFrame({
    ingress,
    roomId: _myRoomId ?? undefined,
    turnActive: () => _turnProjection().working,
    signal,
    isCurrent: () => !_disposed && _state === "started" && connectionIsCurrent() && !signal.aborted,
    onMessage: (message, sender) => _routeClientMessageFrom(
      sender as PlainPeerChannel,
      message,
      _lastEventCtx ?? _lastCtx ?? _noopCtx,
    ),
    onDisconnect: (peerId) => _onPeerDisconnect(peerId),
    sendToPeer: (peerId, message) => _sendOwnerMessageToPeer(peerId, message),
  });
  return signal.aborted ? false : consumed;
}

function _syncOwnerPresenceSubscription(): void {
  _relayTransport.subscribePresence(_owners.peerIds());
}

function _sendOwnerMessageToPeer(peerId: string, message: ServerMessage): void {
  // Handshake and unknown-peer responses always use a transient plaintext
  // channel, including re-pair while an older secure channel is attached.
  let transient: (PeerChannel & { detach(): void }) | null = null;
  try {
    transient = _relayTransport.createPeerChannel({
      peerId,
      roomId: _myRoomId ?? undefined,
      onMessage: () => undefined,
      onDisconnect: () => undefined,
    });
    transient.send(message);
  } catch {
    // Best-effort error/pair response: relay reconnect + app session_sync recover.
  } finally {
    try { transient?.detach(); } catch { /* best-effort transient channel cleanup */ }
  }
}

const _pairingCoordinator = new PairingCoordinator({
  getState: () => _state,
  currentUi: () => {
    const ui = _currentUi();
    return typeof ui?.custom === "function"
      ? ui as Pick<ExtensionContext["ui"], "custom">
      : undefined;
  },
  startRelay: (ctx) => _startRelayViaTransport(ctx),
  isRelayConnected: () => _relayTransport.status() === "connected",
  roomId: () => _myRoomId,
  displayName: (cwd) => _displayName(cwd),
  owners: _owners,
  ownerHas: (peerId) => _owners.has(peerId),
  refreshPairingsCache: () => { void _owners.refreshPairingsCache(); },
  joinLocalMesh: async (ctx) => { if (!_meshNode) await _cmdJoin(ctx); },
  sendPiMessage: (message, options, label) => _sendPiMessage(message, options, label),
  setSiblings: (siblings) => { _meshNode?.setSiblings(siblings); },
});

const _pairingCommands = new PairingCommands(_pairingCoordinator);
const _relayCommands = new RelayCommands(_pairingCoordinator);
const _daemonCommands = new DaemonCommands();
const _cronCommands = new CronCommands();
const _serviceCommands = new ServiceCommands();
// Plan/28 Wave D.1: `thinking` published alongside `model` so the app's
// Quick Actions sheet hydrates the thinking segmented control on first
// open instead of starting null. The SDK fires `thinking_level_select`
// on every change (initial load + user toggle), mirrored to room_meta
// the same way model is — apps subscribe to one channel for both.
let _myRoomMeta: { name: string; cwd: string; session_id?: string; model?: string; thinking?: ThinkingLevel; working?: boolean } | null = null;
let _currentModel: string | undefined = undefined;  // last-known model name
let _currentThinking: ThinkingLevel | undefined = undefined;  // last-known thinking level

// ── Agent-network session (Plan 19) ───────────────────────────────────────────
// MeshNode owns the local UDS mesh plus BrokerRemote/PiForwardClient internals.
// RelayTransport owns when the app relay is handed to MeshNode for cross-PC
// bridge attach/detach during relay start, reconnect, close, and stop.
let _meshNode: MeshNode | null = null;
// Set true by the `session_shutdown` handler. The daemon auto-init defers the
// connect (`setTimeout(_cmdRoot, 0)`) and connecting is async, so a shutdown can
// land WHILE this instance's `_cmdRoot` is still mid-connect (`_meshNode` not
// assigned yet) — the handler would then find nothing to close, and the connect
// would finish afterwards as an unreachable ghost. `_cmdRoot`/`_cmdJoin` check
// this flag after each await and abort (closing any peer that already connected)
// so a torn-down instance never lingers on the broker. Per-module (jiti
// re-evaluates the module on every session replacement), so the replacement
// Starts `true` so the first `session_start` auto-starts the relay (the
// instance starts fresh with `_disposed = false`.
let _disposed = false;

/** Re-queries the broker for the authoritative peer list. The broker's map is
 *  the source of truth — incremental +1/-1 counters drift after failover, lost
 *  `peer_left` broadcasts (e.g., leader leaves), or any dropped event. Called
 *  on every `peer_joined`/`peer_left` and once on join. Fire-and-forget. */
function _refreshSessionPeerCount(
  peer: MeshNode,
  ctx?: Pick<ExtensionContext, "ui"> | null,
): void {
  void peer.request("broker", { type: "list_peers" }, 2000)
    .then((reply) => {
      const peers = (reply.body as { peers?: string[] } | null)?.peers;
      if (Array.isArray(peers)) {
        _owners.setSessionPeerCount(peers.length);
        _refreshFooter(ctx);
      }
    })
    .catch(() => { /* older broker without list_peers — keep prior count */ });
}

/** Friendly model name for room_meta (Plan 18). undefined when SDK has none yet. */
function _currentModelName(): string | undefined {
  return _currentModel;
}

/**
 * Cache the active model name and fan it out to subscribed apps via a
 * `room_meta_update`. The relay push is a no-op when the room isn't up yet —
 * the next `room_meta` hello carries the cached value instead. Shared by the
 * `model_select` event and the connect/turn-start seeding, so a daemon that
 * just runs its DEFAULT model still reports it: `model_select` only fires on an
 * explicit set/cycle (never on settings load), so default-model daemons would
 * otherwise never surface their model.
 */
function _setCurrentModel(name: string): void {
  _currentModel = name;
  _publishRoomMetaPatch({ model: name });
}

/**
 * Plan/32: publish the `working` flag as room_meta (raw, no debounce — the
 * app debounces). Same shape as model/thinking updates. Used by turn_start/end
 * AND by the compaction handlers: `compact()` doesn't run a turn (it
 * disconnects the agent + aborts, emitting compaction_start, NOT turn_start),
 * so room_meta.working must be bracketed manually around compaction.
 */
function _publishWorking(working: boolean): void {
  _publishRoomMetaPatch({ working });
}

function _publishRoomMetaPatch(
  patch: { session_id?: string; model?: string; thinking?: ThinkingLevel; working?: boolean },
): void {
  if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, ...patch };
  _relayTransport.sendRoomMeta(patch);
}

// ── Cross-PC mesh wiring (plan/25 Wave B/C) ───────────────────────────────────

/** Compatibility shim for command-surface call sites that discover the local
 * mesh after relay start. RelayTransport owns the actual bridge lifecycle. */
function _attachBridgeIfReady(): void {
  void _relayTransport.attachCrossPcBridge({
    meshNode: () => _meshNode,
    keypair: () => _pairingCoordinator.currentKeypair() ?? null,
  });
}

type OutpostPiUi = {
  setStatus?: (k: string, v: string | undefined) => void;
  setTitle?: (t: string) => void;
  notify?: (msg: string, type?: "info" | "warning" | "error") => void;
  custom?: ExtensionContext["ui"]["custom"];
};

type OutpostPiUiContext = { ui?: OutpostPiUi } | null | undefined;

/**
 * Safely resolve a ctx.ui reference. Pi intentionally throws when an extension
 * touches a context captured before session replacement/reload; relay callbacks
 * can outlive that context (idle app resumes, known-peer reconnect, late
 * notifications). Treat stale ctxs as absent and clear our captured slots so
 * later callbacks fall through to the freshest session_start ctx or no-op.
 */
function _isStaleContextError(err: unknown): boolean {
  const message = err instanceof Error ? err.message : String(err);
  return message.includes("stale after session replacement or reload");
}

function _safeUi(ctx?: OutpostPiUiContext): OutpostPiUi | undefined {
  if (!ctx) return undefined;
  try {
    return ctx.ui;
  } catch (err) {
    if (_isStaleContextError(err)) {
      if (ctx === _lastCtx) _lastCtx = null;
      if (ctx === _lastEventCtx) _lastEventCtx = null;
    }
    return undefined;
  }
}

function _currentUi(preferred?: OutpostPiUiContext): OutpostPiUi | undefined {
  return _safeUi(preferred) ?? _safeUi(_lastEventCtx) ?? _safeUi(_lastCtx);
}

function _currentCwd(): string {
  if (!_lastCtx) return process.cwd();
  try {
    return "cwd" in _lastCtx ? _lastCtx.cwd : process.cwd();
  } catch {
    _lastCtx = null;
    return process.cwd();
  }
}

function _notify(msg: string, type: "info" | "warning" | "error" = "info", ctx?: OutpostPiUiContext): void {
  const ui = _currentUi(ctx);
  if (typeof ui?.notify !== "function") return;
  try {
    ui.notify(msg, type);
  } catch {
    // Best-effort notification path: stale UI must never crash relay callbacks.
  }
}

/** Surface a delivered capture in the TUI and wake an otherwise idle agent turn. */
export function _sendCaptureDeliveredNote(message: string): void {
  _sendPiMessage(
    { customType: "outpost-pi:debug-capture-delivered", content: message, display: true },
    { triggerTurn: true },
    "debug-capture-delivered",
  );
}

let _captureUploads: CaptureUploadHandler | null = null;

function createCaptureUploadHandler(): CaptureUploadHandler {
  return new CaptureUploadHandler({
    cwd: _currentCwd,
    note: _sendCaptureDeliveredNote,
  });
}

function _replaceCaptureUploadHandler(): void {
  _captureUploads?.dispose();
  _captureUploads = createCaptureUploadHandler();
}

function _disposeCaptureUploadHandler(): void {
  _captureUploads?.dispose();
  _captureUploads = null;
}

/**
 * Adapt command contexts so post-await notifications are best-effort when the
 * captured Pi UI belongs to a replaced session.
 */
function _safeCommandContext<T extends { ui: OutpostPiUi }>(ctx: T): T {
  const ui = _safeUi(ctx);
  return {
    ...ctx,
    ui: {
      ...ui,
      notify: (msg, type = "info") => _notify(msg, type, ctx),
    },
  } as T;
}

function _forgetStaleMessageApi(api: AgentMessageApi): void {
  if (api === _messageApi) _messageApi = null;
  if (api === _pi) _pi = null;
}

function _sessionUnavailable(sender: PlainPeerChannel, inReplyTo: string, detail = "Pi session is replacing or not bound yet"): void {
  _sendRenderableTranscriptError(sender, "internal_error", detail, inReplyTo);
}

function _sendPiMessage(
  message: Parameters<ExtensionAPI["sendMessage"]>[0],
  options?: Parameters<ExtensionAPI["sendMessage"]>[1],
  label = "sendMessage",
): boolean {
  const delivered = _sdkSessionProjection.sendPiMessage(message, options);
  if (!delivered) console.error(`[outpost-pi] ${label}: Pi rejected message: agent session not bound yet`);
  return delivered;
}

/** Refreshes the Pi TUI footer slots from current module state. Safe no-op when ctx lacks ui or is stale. */
function _refreshFooter(ctx?: OutpostPiUiContext): void {
  const ui = _currentUi(ctx);
  if (!ui || typeof ui.setStatus !== "function" || typeof ui.setTitle !== "function") return;
  const ownerSnapshot = _owners.snapshot();
  const state: FooterState = {
    session: ownerSnapshot.sessionName ?? undefined,
    peerCount: ownerSnapshot.sessionPeerCount,
    relayOn: _state !== "idle",
    // `devicePaired` now reflects "any owner currently attached" — picks one
    // shortid representatively (multi-owner UX detail surfaces in the
    // `/outpost-pi status` line, not the footer slot).
    devicePaired: ownerSnapshot.activeOwnerCount > 0 ? ownerSnapshot.lastOwnerShortId : undefined,
    hasPairings: ownerSnapshot.hasGlobalPairings,
    agentName: _meshNode?.name(),
  };
  updateFooter(
    { ui: { setStatus: ui.setStatus.bind(ui), setTitle: ui.setTitle.bind(ui) } },
    state,
  );
}

// SDK session identity, session clock, and transcript replay state are owned by
// SdkSessionProjection. Index keeps only thin compatibility wrappers for legacy
// command/test surfaces.

/**
 * Test-only: emulate what `/outpost-pi` does on the returning-user path
 * (join the local mesh, then start the relay) without touching the FS for
 * a `localConfigExists()` lookup. Lets tests bring the relay up without
 * mocking the wizard or the local config storage.
 *
 * Typed loosely to accept any ctx shape with `ui.notify` + `cwd` — the
 * unit tests use minimal mocks that don't satisfy the full
 * `ExtensionContext` interface.
 */
async function connectForTest(ctx: unknown): Promise<void> {
  const real = ctx as Parameters<typeof _cmdJoin>[0];
  await _cmdJoin(real);
  await _cmdStart(real);
}

/** Test-only: tear everything down (mirrors `/outpost-pi stop`). */
async function stopForTest(ctx: unknown): Promise<void> {
  await _cmdStop(ctx as Parameters<typeof _cmdStop>[0]);
}

/** Test-only: read/reset the `_disposed` flag. In production it's per-module
 *  and never reset (a disposed instance is discarded), but tests share one
 *  module across cases, so they reset it to avoid cross-test pollution. */
export function _getDisposedForTest(): boolean { return _disposed; }
export function _setDisposedForTest(v: boolean): void { _disposed = v; }

/** Test-only: true when this instance holds a live local-mesh node. */
export function _hasMeshNodeForTest(): boolean { return _meshNode !== null; }

/** Test-only: the effective (possibly `#N`-suffixed) name the cwd-lock reserved. */
export function _getLockedNameForTest(): string | null { return _localMeshCommands.getLockedNameForTest(); }

/** Test-only: release + clear the cwd lock (the lock normally survives stop). */
export function _resetCwdLockForTest(): void {
  _localMeshCommands.resetCwdLockForTest();
}

/**
 * Test-only: relay-only startup, no UDS mesh join. Replaces the old
 * `outpost-pi relay start` handler that some tests captured to bring up
 * the relay in isolation (e.g. ping/pong tests that don't care about the
 * agent-network broker).
 */
export async function _startRelayForTest(ctx: unknown): Promise<void> {
  await _cmdStart(ctx as Parameters<typeof _cmdStart>[0]);
}

// Test adapter: routes pre-durable SDK-message fixtures through the production reconciler.
export function _setMessageBufferForTest(msgs: unknown[]): void {
  _sdkSessionProjection.setPreDurableSdkMessagesForTest(msgs);
}

/** Test-only: swap the delivery debug log for a fake, so a test can assert
 *  the expected events fire on a deliver / null-window / re-arm path.
 *  Also re-binds it on the projection so projection-side emits route to the
 *  fake. Returns the previous log so a test can restore it. */
export function _setDeliveryDebugLogForTest(log: DeliveryDebugLog): DeliveryDebugLog {
  const prev = _deliveryDebugLog;
  _deliveryDebugLog = log;
  _sdkSessionProjection.setDeliveryDebugLogForTest(log);
  return prev;
}

/** Test-only: the current delivery debug log (for restore after a test). */
export function _getDeliveryDebugLogForTest(): DeliveryDebugLog {
  return _deliveryDebugLog;
}

export function _setTranscriptEventsForTest(events: TranscriptEvent[]): void {
  _sdkSessionProjection.setTranscriptEventsForTest(events);
}

/** Test-only accessor: returns a defensive copy of the transcript event log. */
export function _getTranscriptEventsForTest(): TranscriptEvent[] {
  return _sdkSessionProjection.getTranscriptEventsForTest();
}

/** Test-only override of session started timestamp. */
export function _setSessionStartedAtForTest(ts: number | null): void {
  _sdkSessionProjection.setSessionStartedAt(ts);
}

export function _getRemoteSessionIdForTest(): string | null {
  return _sdkSessionProjection.currentSessionIdForTest();
}

/** Test-only: simulate the pre-command state where no SDK context is captured. */
export function _clearSdkContextsForTest(): void {
  _sdkSessionProjection.clearStaleContexts();
}

export function _setRemoteSessionIdForTest(id: string | null): void {
  _sdkSessionProjection.setSessionIdForTest(id);
}

function _currentRemoteSessionId(ctx?: unknown): string {
  return _sdkSessionProjection.currentRemoteSessionId(ctx ?? _lastEventCtx ?? _lastCtx ?? undefined);
}

function _withCurrentSession<T extends object>(msg: T): T & { session_id: string } {
  return _sdkSessionProjection.currentSessionMessage(msg);
}

function _recordDurableTranscriptEvent(event: TranscriptEvent): TranscriptRecordResult {
  return _sdkSessionProjection.recordDurableTranscriptEvent(event);
}

function _isAuthoritativeTranscriptRecord(result: TranscriptRecordResult): boolean {
  return result.status === "recorded" || result.status === "duplicate";
}

/** Persist one renderable diagnostic before sending its live projection.
 *
 * A missing durable writer falls back to a ts-less compatibility frame so an
 * older/mid-replacement session still renders live without claiming durable
 * replay authority.
 */
function _sendRenderableTranscriptError(
  sender: PlainPeerChannel | null,
  code: "provider_error" | "internal_error",
  message: string,
  inReplyTo?: string,
): void {
  const sessionId = _currentRemoteSessionId();
  const producedAt = Date.now();
  const eventId = deterministicTranscriptEventId(
    sessionId,
    "provider_error",
    inReplyTo ?? String(producedAt),
  );
  const recorded = _recordDurableTranscriptEvent({
    kind: "provider_error",
    eventId,
    sessionId,
    ts: producedAt,
    ...(inReplyTo ? { replyTo: inReplyTo } : {}),
    code,
    message,
  });
  const authoritative = _isAuthoritativeTranscriptRecord(recorded);
  const error = _withCurrentSession({
    type: "error" as const,
    ...(inReplyTo ? { in_reply_to: inReplyTo } : {}),
    code,
    message,
    ...(authoritative
      ? { ts: _sdkSessionProjection.recordedTranscriptTs(eventId) ?? producedAt }
      : {}),
  });
  if (sender) sender.send(error);
  else _owners.broadcast(error);
}

function _compactionTimestamp(value: unknown, fallback: number): number {
  if (typeof value !== "string") return fallback;
  const parsed = Date.parse(value);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : fallback;
}

function _rememberDeliveredUserEvent(
  text: string,
  images: readonly { data: string; mime: string }[] | undefined,
  clientMessageId: string,
  eventId: string,
): () => void {
  return _sdkSessionProjection.rememberDeliveredUserEvent(text, images, clientMessageId, eventId);
}

function _recordSdkMessageTranscriptEvents(message: SdkTranscriptMessage): void {
  _sdkSessionProjection.recordSdkMessageTranscriptEvents(message);
}

function _captureRemoteSession(ctx: unknown): string {
  return _sdkSessionProjection.captureRemoteSession(ctx);
}

/** Test-only: reset the cached model name (between tests). */
export function _setCurrentModelForTest(name: string | undefined): void {
  _currentModel = name;
}

/** Test-only: read the active turn id used for plain `cancel` routing. */
export function _getCurrentTurnIdForTest(): string | null {
  return _turnProjection().activeTurnId;
}

/** Test-only: inspect the reducer-owned turn projection without exposing internals. */
export function _getTurnProjectionForTest(): TurnProjection {
  return _turnProjection();
}

/** Test-only: override the bound AgentSession so a spy can capture the
 *  content handed to `sendUserMessage` (plan/30 multimodal ingest). */
export function _setPiForTest(pi: unknown): void {
  if (pi && typeof pi === "object" && !("appendEntry" in pi)) {
    Object.defineProperty(pi, "appendEntry", { value: () => undefined, configurable: true });
  }
  _pi = pi as typeof _pi;
  _messageApi = _isAgentMessageApi(pi) ? pi : null;
  _sdkSessionProjection.clearApiBindings();
  if (_pi) {
    _sdkSessionProjection.bindApi(_pi);
    _drainPendingDeliveryQueue();
  }
}

/** Test-only: clear replay queue/timers between focused lifecycle tests. */
export function _resetPendingDeliveryQueueForTest(): void {
  for (const entry of _pendingDeliveryQueue) clearTimeout(entry.timeout);
  _pendingDeliveryQueue = [];
  _inflightUserDeliveries.clear();
}

/** Test-only: expose bounded replay queue depth for regression assertions. */
export function _getPendingDeliveryQueueLengthForTest(): number {
  return _pendingDeliveryQueue.length;
}

/** Test-only: simulate the `withSession` (mobile `session_new`) re-arm path
 * draining the pending delivery queue, without driving the full SDK
 * replacement. Mirrors what `_bindReplacementSessionContext` does after
 * re-arming `_messageApi` from a fresh replacement context: arm the
 * projection's messageApi (so `wakeAgent` sees it) then drain. */
export function _drainAfterReplacementForTest(freshMessageApi: unknown): void {
  _pi = freshMessageApi as typeof _pi;
  _messageApi = _isAgentMessageApi(freshMessageApi) ? freshMessageApi : null;
  if (_messageApi) _sdkSessionProjection.bindApi(_messageApi as never);
  _drainPendingDeliveryQueue();
}

/**
 * Persist a model change to the PROJECT settings (`<cwd>/.pi/settings.json`) so
 * a model picked from the app survives a Pi/daemon restart. `pi.setModel` only
 * sets the LIVE model — on the next restart a fresh session reads the saved
 * default and reverts (the reported bug). We write the PROJECT scope, NOT
 * global, deliberately: the SDK merges global←project with PROJECT winning
 * (`SettingsManager`), so a folder that already has a project default (every
 * created daemon does) would shadow a global write like the TUI's. Project
 * scope is also correct for a fleet — each daemon keeps its own model rather
 * than leaking one default globally.
 *
 * Read-merge-write + best-effort: preserves other keys and never throws (a
 * settings write must not fail the live model change, which already applied).
 */
function _persistModelDefault(provider: string, modelId: string): void {
  try {
    const path = join(process.cwd(), ".pi", "settings.json");
    let obj: Record<string, unknown> = {};
    try {
      const parsed = JSON.parse(readFileSync(path, "utf8")) as unknown;
      if (parsed && typeof parsed === "object") obj = parsed as Record<string, unknown>;
    } catch { /* no existing/parseable file → start fresh */ }
    obj["defaultProvider"] = provider;
    obj["defaultModel"] = modelId;
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, JSON.stringify(obj, null, 2));
  } catch { /* best-effort — model change already applied live */ }
}

function _turnProjection(): TurnProjection {
  return _sdkSessionProjection.turnProjection();
}

function _applyTurnAndPublish(event: TurnEvent): TurnProjection {
  const projection = _sdkSessionProjection.applyTurn(event);
  if (event.type === "turn_end") _owners.completeOfflineTurn();
  return projection;
}

function _resetTurnSnapshot(): void {
  _sdkSessionProjection.resetTurnSnapshot();
}

function _activeReplyTarget(): string | null {
  const projection = _turnProjection();
  return projection.replyTo ?? projection.activeTurnId;
}

// Module-level pi reference
let _pi: ExtensionAPI | null = null;

// ── Relay reconnect state ─────────────────────────────────────────────────────
// Backoffs in ms: 1s, 2s, 5s, 10s, 30s, then stays at 30s; the transport
// adapter owns the timer/counter and this test hook observes that owner.

/** Test-only: exposes pending reconnect timer state. */
export function _hasPendingReconnect(): boolean {
  return _relayTransport.hasPendingReconnect();
}

/**
 * Public state-snapshot helper. Returns the derived UX state, not the raw
 * `_state` enum: the W2D refactor collapsed the internal machine to
 * `idle | started` and made `paired` a derived metric
 * (`ownerMultiplexer.activeCount() > 0`). Tests and the footer keep the
 * three-state mental model via this getter.
 */
function getStateForTest(): "idle" | "started" | "paired" {
  if (_state === "idle") return "idle";
  return _owners.activeCount() > 0 ? "paired" : "started";
}

/**
 * Test-only: the room this Pi currently has registered with the relay, or `null`
 * while idle. Gates on `_state` because `_goIdle` clears the relay session but
 * does not clear `_myRoomId` — returning the stale room while idle would violate
 * the accessor's contract. Authoritative App↔Pi room — see
 * `OutpostPiTestHarness.roomId`.
 */
function getRoomIdForTest(): string | null {
  return _state === "idle" ? null : _myRoomId;
}

/** Test-only: number of owners currently attached through managed owner channels. */
export const _getActivePeerCountForTest = (): number => ownerHarness.activeOwnerCount();

/** Test-only: true if a specific peer (base64 std) has an attached channel. */
export const _hasActivePeerForTest = (appPeerIdStd: string): boolean => ownerHarness.hasOwner(appPeerIdStd);


// ── Multi-channel helpers ─────────────────────────────────────────────────────

function _currentQueueStateMessage(): Extract<ServerMessage, { type: "queued_message_state" }> {
  return _sdkSessionProjection.queuedMessageState();
}

function _broadcastQueuedMessageState(): void {
  _sdkSessionProjection.broadcastQueuedMessageState();
}

// ── Display-name helpers ──────────────────────────────────────────────────────

/**
 * Resolves the name this Pi shows to the mobile app and the relay's
 * `room_meta.name`. Single source of truth for "what does this Pi call
 * itself when talking to others".
 *
 * Resolution order:
 *   1. Broker-assigned name (when this Pi is on the local UDS mesh) — may
 *      carry a `#N` suffix from a name collision. Matches what other
 *      agents see, so the mobile UI shows the exact same string.
 *   2. `agent_name` from `<cwd>/.pi/outpost-pi/config.json` — set by the
 *      wizard on first run; this is "the name the user configured".
 *   3. `defaultAgentName(cwd)` (parent/folder) — fallback when no config
 *      exists yet and the mesh hasn't been joined.
 *
 * Pre-2026-05-23 callers computed `cwd.split('/').slice(-2).join('/')`
 * inline at three different sites (pair_ok, room_meta, QR URI); this
 * helper consolidates them and lifts the user's configured name above
 * the raw cwd path.
 */
function _displayName(cwd: string): string {
  if (_meshNode) return _meshNode.name();
  const local = loadLocalConfig(cwd);
  return local.agent_name || defaultAgentName(cwd);
}

// ── Transition helpers ────────────────────────────────────────────────────────

let _goIdleInFlight: Promise<void> | null = null;

/**
 * Drain every owner channel before closing the shared relay and becoming idle.
 *
 * Overlapping lifecycle and command stops share one completion boundary. Owner
 * drains end after local persistence and synchronous relay enqueue; they never
 * wait for a relay ACK or future inbound frame.
 */
function _goIdle(byeReason?: import("./protocol/types.js").ByeReason): Promise<void> {
  if (_goIdleInFlight) return _goIdleInFlight;

  const teardown = async (): Promise<void> => {
    _stopOwnerIngressListener();
    // The poller is relay-lifecycle-owned and must not race a new detach while
    // the current owner snapshot drains.
    _pairingCoordinator.stopSelfRevoke();

    const ownerIds = [..._owners.peerIds()];
    const drains = ownerIds.map((peerId) => _owners.detach(peerId, byeReason));
    _captureUploads?.detachAll();

    // Preserve turn convergence while the relay remains usable. This is the
    // last chance to publish working=false on session replacement/shutdown.
    _applyTurnAndPublish({ type: "session_shutdown" });
    _resetTurnSnapshot();
    _publishWorking(false);

    // One failed owner drain must not strand the shared runtime. allSettled
    // observes every rejection before the relay is closed.
    await Promise.allSettled(drains);

    // Cancel any pending reconnect attempt and close the live relay only after
    // protected bye persistence/enqueue has settled for every snapshotted owner.
    await _relayTransport.stop(byeReason);

    // Preserve projection-owned sessionStartedAt + transcript events across
    // stop/start cycles. The Pi agent session outlives the relay connection —
    // `message_end` keeps firing for terminal turns even while idle, and the
    // transcript event log must survive so those turns appear in session_sync.
    // Only Pi session replacement resets these.
    _state = "idle";
    _refreshFooter();
    _emitRelayState();  // → disconnected
  };

  const inFlight = teardown();
  _goIdleInFlight = inFlight;
  void inFlight.then(
    () => { if (_goIdleInFlight === inFlight) _goIdleInFlight = null; },
    () => { if (_goIdleInFlight === inFlight) _goIdleInFlight = null; },
  );
  return inFlight;
}

/**
 * Called when the relay WS closes unexpectedly (network drop, relay restart,
 * etc.). Does a **partial** teardown — keeps projection-owned session clock,
 * transcript events, and relay-transport-owned retry state so the session can resume on reconnect.
 *
 * Peer (app) reconnect after a successful relay reconnect is handled by the
 * transport-owned ingress subscription via `peers.json` lookup, so we don't
 * need to track the prior peer here; we just go back to `started` and wait.
 */
function _onRelayClose(): void {
  if (_state === "idle") return;  // already torn down (e.g. /outpost-pi stop)

  // Keep owner ingress subscribed through the relay transport so the fresh
  // reconnect socket can reattach known peers from their first post-reconnect
  // message. Only per-owner channels are relay-socket-specific.

  // Detach every per-owner channel — relay is gone, none can route. The
  // ingress handler re-attaches owners after `_attemptReconnect` succeeds
  // (via the same known-peer + pair_request paths used on first connect).
  // Relay drop is not an explicit stop: do not send bye and do not clear
  // session history or reconnect-owned state.
  _owners.detachAllForRelayDrop();
  if (!_turnProjection().working) _resetTurnSnapshot();

  _state = "started";
  _refreshFooter();
}

// ── Relay state event + transparent control channel (Cockpit toggle) ─────────

/** Current relay connectivity, derived by the relay transport adapter. */
function _relayStatus(): RelayConnectivity {
  if (getStateForTest() === "idle") return "disconnected";
  return _relayTransport.status();
}

/**
 * Ask the relay transport to emit the `outpost-pi:relay-state` custom message.
 * The transport owns the dedupe and snapshot shape; index only bridges to Pi's
 * message API.
 */
function _emitRelayState(force = false): void {
  _relayTransport.emitRelayState(force);
}

function _sendRelayStateSnapshot(snapshot: RelayStateSnapshot): void {
  // Relay-state is display telemetry, never a load-bearing send. Suppress it
  // entirely when no Pi session is bound (startup race before session_start,
  // or during session_shutdown). The replacement instance / withSession rearm
  // publishes its own fresh state once bound.
  if (!_sdkSessionProjection.messageApiBinding()) return;
  _sendPiMessage({
    customType: "outpost-pi:relay-state",
    content: `Relay ${snapshot.status}`,
    details: {
      status: snapshot.status,
      connected: snapshot.connected,
      ...(snapshot.relayUrl ? { relayUrl: snapshot.relayUrl } : {}),
      ...(snapshot.room ? { room: snapshot.room } : {}),
    },
    display: false,
  }, undefined, "relay-state");
}

/** Minimal ctx for relay start/stop driven by a control message (no command
 *  ctx is available in the `input` hook). cwd matches the daemon's launch dir,
 *  so the derived relay room is identical to the one `_cmdStart` first used. */
function _controlCtx(): Pick<ExtensionContext, "ui" | "cwd"> {
  return {
    ui: _headlessUi(),
    cwd: process.cwd(),
  } as unknown as Pick<ExtensionContext, "ui" | "cwd">;
}

/**
 * `ui.notify` for headless contexts (daemon auto-init + control channel). There
 * is no TUI, and the RPC client (Cockpit) already gets everything it needs via
 * structured events (`outpost-pi:relay-state`, `outpost-pi:name-assigned`,
 * room_meta) — so routine INFO chatter would just pollute the client's captured
 * stderr. We drop info and forward only warnings/errors (kept for the
 * supervisor's journal / genuine failures). The interactive Pi keeps its normal
 * footer/notify path — this only affects headless ctxs.
 */
function _headlessUi(): { notify: (msg: string, type?: "info" | "warning" | "error") => void } {
  return {
    notify: (msg: string, type?: "info" | "warning" | "error") => {
      if (type === "warning" || type === "error") process.stderr.write(`${msg}\n`);
    },
  };
}

/**
 * Handle a transparent control command from an RPC client (Cockpit), received
 * as a `CTRL_PREFIX`-tagged input the `input` hook swallowed. Toggles the relay
 * WITHOUT leaving the local mesh (relay-only: `_cmdStart` up / `_goIdle` down),
 * then emits the fresh state. `relay:status` just re-emits (no change) so the
 * client can sync its button after (re)attaching to the RPC stream.
 */
export async function _handleControl(cmd: string): Promise<void> {
  await _localMeshCommands.handleControl(cmd);
}

function _dispatchControlFrame(frame: ParsedControlFrame): void {
  void _handleControl(frame.command).catch((error: unknown) => {
    console.error(`[outpost-pi] control command failed: ${String(error)}`);
  });
}

/**
 * Per-owner disconnect callback. Fires when one specific owner's channel
 * detaches (e.g. relay told us the peer is gone). Other owners' channels
 * keep running — relay stays "started".
 *
 * Exported so tests can trigger the disconnect path for a specific peer.
 *
 * Backward-compat: a no-arg call (legacy tests / pre-W2D callers) falls
 * back to detaching the most recently attached peer, mirroring the old
 * singleton semantics.
 */
function _disconnectOwnerForRuntime(appPeerId?: string): void {
  if (_state === "idle") return;
  const detachedOwnerId = appPeerId ?? _owners.peerIds().at(-1);
  const result = _owners.disconnectOwner(appPeerId);
  if (!result.disconnected) return;
  if (detachedOwnerId) _captureUploads?.detachOwner(detachedOwnerId);

  _syncOwnerPresenceSubscription();

  if (result.activeOwnerCount > 0) {
    // Other owners still attached — keep the turn projection so they continue
    // seeing the in-flight agent stream.
    _refreshFooter();
    return;
  }

  // No owner left. Keep the turn projection active so a later attach during the
  // same turn can still receive chunks/done; the reducer clears only on terminal events.
  if (!_turnProjection().working) _resetTurnSnapshot();
  _refreshFooter();
  _notify("[outpost-pi] All app peers disconnected, listening for reconnect", "info");
  // Auto-listener stays up — same listener catches the reconnect on any peer.
}

export const _onPeerDisconnect = (appPeerId?: string): void => ownerHarness.disconnectOwner(appPeerId);

/**
 * Plan/27 Wave A: lazily resolve the pi-extension package version from
 * disk so the `pair_ok.harness.version` field reflects what's actually
 * shipped. The lookup is best-effort — a parse failure (or running this
 * file out-of-tree) falls back to "0.0.0" which is still semver-valid
 * and the app tolerates it. Cached at module load.
 */
function _readExtensionVersion(): string {
  try {
    const here = fileURLToPath(import.meta.url);
    // dist/index.js → ../package.json. src/index.ts under tsx → also one level up.
    const pkgPath = join(here, "..", "..", "package.json");
    const pkg = JSON.parse(readFileSync(pkgPath, "utf8")) as { version?: string };
    return typeof pkg.version === "string" ? pkg.version : "0.0.0";
  } catch {
    return "0.0.0";
  }
}
const _HARNESS = {
  name: "Pi coding agent",
  version: _readExtensionVersion(),
} as const;
const _HOSTNAME = hostname();

// ── Extension factory (default export) ───────────────────────────────────────

// Stores most recent command context so the auto-listener can use ui.notify.
// NOTE: this is a CAPTURED command ctx — the SDK marks it stale after a
// session replacement (newSession/fork/switch/reload). We re-capture it via
// `withSession` when WE drive a newSession (see the session_new dispatch).
let _lastCtx: Pick<ExtensionContext, "ui" | "abort" | "cwd"> | null = null;
// Freshest base ExtensionContext, re-captured on EVERY `session_start`
// (startup/new/fork/reload/resume). The session_start ctx is always bound to
// the CURRENT session, so compact + cancel (base-ctx methods) routed through
// here never hit a stale ctx — regardless of who triggered the replacement
// (an app Quick Action OR a `/new` typed in the Pi TUI). It carries only
// base-ctx methods (no newSession — that's command-ctx only), so command ops
// keep using `_lastCtx`.
let _lastEventCtx: Pick<ExtensionContext, "compact" | "abort" | "ui"> | null = null;
const _noopCtx = { ui: { notify: () => undefined }, abort: () => undefined };

type AgentMessageApi = {
  sendMessage: (...args: Parameters<ExtensionAPI["sendMessage"]>) => void | Promise<void>;
  sendUserMessage: (...args: Parameters<ExtensionAPI["sendUserMessage"]>) => void | Promise<void>;
};
let _messageApi: AgentMessageApi | null = null;
let _activeOutpostPiRuntime: OutpostPiRuntime | null = null;

function _isAgentMessageApi(value: unknown): value is AgentMessageApi {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<AgentMessageApi>;
  return typeof candidate.sendMessage === "function" && typeof candidate.sendUserMessage === "function";
}

let _deliveryDebugLog = createDeliveryDebugLog();

const _sdkSessionProjection: SdkSessionProjection = new SdkSessionProjection({
  outputs: {
    broadcast: (message) => _owners.broadcast(message),
    sendTo: (sender, message) => sender.send(message),
    publishRoomMeta: (patch) => _publishRoomMetaPatch(patch),
    activeOwnerIds: () => _owners.peerIds(),
    lateAttachTargets: () => _owners.lateAttachEntries(),
    handleClientMessage: (sender, message) => _routeClientMessageFrom(sender as PlainPeerChannel, message, _lastEventCtx ?? _lastCtx ?? _noopCtx),
    onStaleMessageApi: (api) => _forgetStaleMessageApi(api),
    onMeshDeliveryFailure: (reason) => {
      console.error(`[outpost-pi] queued mesh delivery failed: ${reason}`);
      _notify("[outpost-pi] failed to process queued mesh messages", "error");
    },
    deliveryDebugLog: _deliveryDebugLog,
  },
});

const extension: ExtensionFactory = (pi: ExtensionAPI): void => {
  const runtimePorts = createRuntimePorts();
  const runtime = createOutpostPiExtensionRuntime(pi, runtimePorts);
  // Every ordinary SDK event is factory-local. Satellite/child factories still
  // register a complete extension surface, but their callbacks cannot mutate
  // the phone-facing process singleton.
  const ownerPi = new Proxy(pi, {
    get(target, property, receiver) {
      if (property === "on") {
        return (event: string, handler: (...args: unknown[]) => unknown) => {
          const register = target.on as unknown as (
            name: string,
            callback: (...args: unknown[]) => unknown,
          ) => void;
          register(event, (...args: unknown[]) => {
            if (!runtime.isOwner()) return undefined;
            return handler(...args);
          });
        };
      }
      if (property === "registerCommand") {
        return (name: string, options: { handler: (...args: unknown[]) => unknown }) => {
          const register = target.registerCommand as unknown as (
            commandName: string,
            commandOptions: { handler: (...args: unknown[]) => unknown },
          ) => void;
          register(name, {
            ...options,
            handler: (...args: unknown[]) => {
              if (!runtime.isOwner()) return undefined;
              return options.handler(...args);
            },
          });
        };
      }
      return Reflect.get(target, property, receiver) as unknown;
    },
  });

  // Plan 19: ensure ~/.pi/remote/{sessions,skills}/ exist. The command
  // surface deploys the agent-network skill when it registers.
  try {
    ensureGlobalDirs();
  } catch { /* best-effort init */ }

  ownerPi.on("resources_discover", () => ({ skillPaths: [skillsDir()] }));

  // Tool calls execute without prompting the remote user. The Pi SDK has no
  // native `requiresApproval` per tool, and a hardcoded gate (Bash/Edit/Write)
  // misfired on every custom tool from third-party packages. Approval will
  // come back when the Pi ecosystem ships a permissions convention. tool_result
  // is still forwarded so the app shows tool activity transparently.

  // Mirror input typed in the Pi terminal (or sent via RPC) to every
  // connected owner. 'extension' source is our own sendUserMessage call
  // from routeClientMessage, which already seeded the turn projection — skip to
  // avoid a double turnId.
  ownerPi.on("input", (event) => {
    // Subagent-leak gate: the subagent's dispatch prompt reaches the child
    // session via `session.prompt()` (`@gotgenes/pi-subagents`
    // `subagent-session.ts:120`), which the SDK fires as an `input` event with
    // `source: "interactive"` (the default — the subagent passes no source).
    // So the `if (event.source === "extension") return;` guard below does NOT
    // skip it, and without this gate the dispatch prompt would broadcast as a
    // `user_input` chat bubble on mobile (confirmed live 2026-07-07: "Reply
    // with exactly..." was the final visible message). Suppress while a
    // subagent tool execution is open. See
    // story-extension-suppress-subagent-assistant-broadcast.
    if (subagentGate.isActive()) return;
    // Transparent control channel: structured `outpost_pi_control` frames are
    // the canonical path; `CTRL_PREFIX` remains an explicit compatibility
    // decoder. Both map to one dispatch path and are SWALLOWED
    // (`action:"handled"`) so they never reach the LLM or the transcript.
    // Checked first, before the peer-broadcast path, and regardless of source.
    const controlFrame = _parseControlFrame(event.text);
    if (controlFrame) {
      _dispatchControlFrame(controlFrame);
      return { action: "handled" } as const;
    }
    if (event.source === "extension") return;
    const before = _turnProjection();
    const turnId = before.replyTo ?? before.activeTurnId ?? `local_${randomUUID()}`;
    _applyTurnAndPublish({ type: "local_input", turnId, replyTo: turnId, source: "local" });
    // Do NOT broadcast a `user_input` frame here. The SDK fires `message_end`
    // for the user prompt milliseconds later (before `runLoop`/agent streaming —
    // `pi-agent-core/dist/agent-loop.js:48-54`), and the durable transcript
    // recorder broadcasts a `user_input` with the stable SDK `ts` + `id = clientMessageId`
    // from there. This earlier broadcast used a different `id` (`turnId` =
    // `local_<uuid>`) and no `ts`, so the app committed it under
    // `'server:user_confirmed:$turnId'` — a SECOND row that didn't collapse
    // with the `message_end`-driven deterministic row → duplicate user bubble
    // for workstation-typed messages (confirmed 2026-07-08: operator saw their
    // own TUI-typed message doubled on mobile). The turn projection is still
    // seeded above so `message_end`'s `lastTranscriptUserId` / replyTo resolves.
    // See story-mobile-assistant-message-duplicated-live-replay (user-message
    // identity, the deferred early-echo suppression — now applied to the
    // `input`-handler path too).
    return undefined;
  });

  // Track active model so the app can show it in the SessionTile (Plan 18).
  // SDK fires model_select on settings load + every user switch. We cache the
  // friendly name and broadcast a room_meta_update so the relay can fan it
  // out to subscribed apps without needing a new pair.
  ownerPi.on("model_select", (event) => {
    const m = event?.model as { name?: string; id?: string } | undefined;
    const modelName = m?.name ?? m?.id;
    if (!modelName) return;
    // Cache + fan out. Keeps the cached room_meta fresh so a future reconnect
    // carries the current model in its hello, and pushes a room_meta_update to
    // apps already subscribed.
    _setCurrentModel(modelName);
  });

  // Plan/28 Wave D.1: mirror model's room_meta_update path for thinking
  // level so the app hydrates the segmented control on first open instead
  // of starting null. SDK fires `thinking_level_select` on settings load
  // AND on every user toggle (matching `model_select`'s behavior), so
  // late-pairing apps see the current level via `room_meta_updated`.
  ownerPi.on("thinking_level_select", (event) => {
    const level = event?.level as ThinkingLevel | undefined;
    if (!level) return;
    _currentThinking = level;
    _publishRoomMetaPatch({ thinking: level });
  });

  ownerPi.on("message_update", (event) => {
    const ae = event.assistantMessageEvent;
    if (ae.type !== "text_delta") return;
    // Subagent-leak gate: the subagent's reply streams token-by-token via
    // `message_update` (text_delta) BEFORE `message_end` fires. Gate this
    // path too, or the streaming `agent_chunk`s reach the phone even when
    // the `message_end` broadcast is suppressed. See
    // `story-extension-suppress-subagent-assistant-broadcast`.
    if (subagentGate.isActive()) return;
    const projection = _applyTurnAndPublish({ type: "agent_chunk" });
    const replyTo = projection.replyTo ?? projection.activeTurnId;
    if (_owners.activeCount() === 0 || replyTo === null) return;
    _owners.broadcast(_withCurrentSession({ type: "agent_chunk", in_reply_to: replyTo, delta: ae.delta }));
  });

  // Notify every connected owner that a tool is about to run (visibility
  // only, NOT approval). tool_execution_start fires before the tool
  // executes; tool_execution_end closes the loop with the result. Together
  // they render a "Tool running… done" timeline in each paired app.
  ownerPi.on("tool_execution_start", (event) => {
    subagentGate.enter(event.toolName);
    const sessionId = _currentRemoteSessionId();
    const args = _enrichToolArgs(event.toolName, event.args);
    const eventId = deterministicTranscriptEventId(sessionId, "tool_requested", event.toolCallId);
    const producedAt = Date.now();
    const recorded = _recordDurableTranscriptEvent({
      kind: "tool_requested",
      eventId,
      sessionId,
      ts: producedAt,
      toolCallId: event.toolCallId,
      tool: event.toolName,
      args,
    });
    if (!_isAuthoritativeTranscriptRecord(recorded) || _owners.activeCount() === 0) return;
    const ts = _sdkSessionProjection.recordedTranscriptTs(eventId) ?? producedAt;
    _owners.broadcast(_withCurrentSession({
      type: "tool_request",
      tool_call_id: event.toolCallId,
      tool: event.toolName,
      args,
      ts,
    }));
  });

  ownerPi.on("tool_execution_end", (event) => {
    subagentGate.exit(event.toolName);
    // Stringify through the transcript projection helper so live == re-sync.
    const text = stringifyToolResult(event.result);
    const sessionId = _currentRemoteSessionId();
    const eventId = deterministicTranscriptEventId(sessionId, "tool_finished", event.toolCallId);
    const producedAt = Date.now();
    const recorded = _recordDurableTranscriptEvent(event.isError
      ? {
          kind: "tool_finished",
          eventId,
          sessionId,
          ts: producedAt,
          toolCallId: event.toolCallId,
          error: text,
        }
      : {
          kind: "tool_finished",
          eventId,
          sessionId,
          ts: producedAt,
          toolCallId: event.toolCallId,
          result: text,
        });
    if (!_isAuthoritativeTranscriptRecord(recorded) || _owners.activeCount() === 0) return;
    const ts = _sdkSessionProjection.recordedTranscriptTs(eventId) ?? producedAt;
    const msg: ServerMessage = event.isError
      ? _withCurrentSession({ type: "tool_result", tool_call_id: event.toolCallId, error: text, ts })
      : _withCurrentSession({ type: "tool_result", tool_call_id: event.toolCallId, result: text, ts });
    _owners.broadcast(msg);
  });

  // Current user and assistant text facts cross the durable transcript boundary
  // from `message_end`, including turns initiated from the Pi terminal or RPC.
  // Tool-call blocks and toolResult messages stay LLM-context-only here: the
  // execution hooks above are their sole transcript producers.
  ownerPi.on("message_end", (event) => {
    const m = event?.message as { role?: string; stopReason?: string; errorMessage?: string } | undefined;
    if (!m) return;
    // Subagent-leak gate: while a `subagent` tool execution is open, the child
    // session's user/assistant message_end events are not owner transcript facts.
    const suppressForSubagent = (m.role === "assistant" || m.role === "user") && subagentGate.isActive();
    if (!suppressForSubagent && (m.role === "user" || m.role === "assistant")) {
      _recordSdkMessageTranscriptEvents(m as unknown as SdkTranscriptMessage);
    }
    // Forward a failed turn to connected owners. Without this the app just
    // hangs with no response when the provider errors (e.g. the TUI's
    // "Provider finish_reason: error"): the SDK surfaces the failure as an
    // assistant message with stopReason "error" + an `errorMessage` (pi-ai).
    // `error` is an existing ServerMessage the app already renders — no
    // protocol/app change. `in_reply_to` ties it to the turn the app awaits.
    if (!suppressForSubagent && m.role === "assistant" && m.stopReason === "error") {
      const message = typeof m.errorMessage === "string" && m.errorMessage
        ? m.errorMessage
        : "Provider error";
      const replyTo = _activeReplyTarget();
      _applyTurnAndPublish({ type: "provider_error", turnId: replyTo });
      _sendRenderableTranscriptError(null, "provider_error", message, replyTo ?? undefined);
    }
  });

  ownerPi.on("agent_start", () => {
    runtime.ports.session.markAgentRunStarted();
  });

  ownerPi.on("agent_end", () => {
    // Message content is fed by `message_end`; here we record the terminal
    // assistant_done boundary and finalize the outbound turn signal.
    const before = _turnProjection();
    const finishedTurnId = before.replyTo ?? before.activeTurnId;
    if (finishedTurnId === null) return;
    const sessionId = _currentRemoteSessionId();
    const eventId = deterministicTranscriptEventId(sessionId, "assistant_done", finishedTurnId);
    const producedAt = Date.now();
    const recorded = _recordDurableTranscriptEvent({
      kind: "assistant_done",
      eventId,
      sessionId,
      ts: producedAt,
      replyTo: finishedTurnId,
    });
    _applyTurnAndPublish({ type: "agent_done" });
    if (_isAuthoritativeTranscriptRecord(recorded) && _owners.activeCount() > 0) {
      const ts = _sdkSessionProjection.recordedTranscriptTs(eventId) ?? producedAt;
      _owners.broadcast(_withCurrentSession({ type: "agent_done", in_reply_to: finishedTurnId, ts }));
    }
    _maybeSendLateAttachSessionSync();
    _maybeDrainQueuedMessage();
  });

  // plan/34: the broker no longer gates delivery on busy state, so we no
  // longer notify it of turn lifecycle. Working state is still published as
  // room_meta over the relay (plan/32) below — that's independent of the
  // broker and drives the app's working indicator.
  ownerPi.on("turn_start", (_event, ctx) => {
    const fallbackTurnId = _turnProjection().replyTo ?? _turnProjection().activeTurnId ?? `local_${randomUUID()}`;
    _applyTurnAndPublish({ type: "turn_start", fallbackTurnId });
    // Late model hydration: if the model was still unknown at connect (resolved
    // lazily by the SDK), grab it on the first turn and fan it out — so a daemon
    // whose model only materialises at turn 1 still reports it to the app.
    if (!_currentModel) {
      try {
        const m = (ctx as Partial<ExtensionContext> & { getModel?: () => { name?: string; id?: string } | undefined }).getModel?.();
        const name = m?.name ?? m?.id;
        if (name) _setCurrentModel(name);
      } catch { /* defensive — never block a turn on a model lookup */ }
    }
    // Plan/32 Part B: room_meta.working is published by the turn projection diff.
  });
  ownerPi.on("turn_end", () => {
    const before = _turnProjection();
    const after = _applyTurnAndPublish({ type: "turn_end" });
    if (!before.working && !after.working) _publishWorking(false);
    _maybeSendLateAttachSessionSync();
    _maybeDrainQueuedMessage();
  });

  // agent_settled is the first boundary after retries, compaction, and queued
  // continuations have drained. Keep this handler synchronous: the ingress gate
  // must be visible before the handler returns so a new prompt cannot start
  // between settlement and the graceful process shutdown.
  ownerPi.on("agent_settled", (_event, ctx) => {
    runtime.ports.session.markAgentSettled();
    _maybeRestartForExtensionReload(ctx);
  });

  // Plan/32: compaction feedback. compact() doesn't run a turn, so bracket it
  // with working=true/false here. Returning void = no veto → default
  // compaction proceeds.
  ownerPi.on("session_before_compact", () => {
    _applyTurnAndPublish({ type: "compaction_start", turnId: `compact_${randomUUID()}` });
  });
  ownerPi.on("session_compact", (event) => {
    const entry = event?.compactionEntry as {
      summary?: unknown;
      tokensBefore?: unknown;
      timestamp?: unknown;
    } | undefined;
    const summary = typeof entry?.summary === "string" ? entry.summary : "";
    const tokensBefore = typeof entry?.tokensBefore === "number" ? entry.tokensBefore : 0;
    const ts = _compactionTimestamp(entry?.timestamp, Date.now());
    // (2) The CompactionEntry never reaches message_end. Its SDK timestamp is
    // also the mixed-era raw-entry identity, so the durable fact can suppress
    // that fallback exactly after reopen.
    const sessionId = _currentRemoteSessionId();
    const recorded = _recordDurableTranscriptEvent({
      kind: "compaction_recorded",
      eventId: deterministicTranscriptEventId(sessionId, "compaction_recorded", String(ts)),
      sessionId,
      ts,
      summary,
      tokensBefore,
    });
    // (1) A transcript marker becomes live only after durable authority exists.
    if (_isAuthoritativeTranscriptRecord(recorded)) {
      _owners.broadcast(_withCurrentSession({ type: "compaction", summary, tokens_before: tokensBefore, ts }));
    }
    // (3) Working ends independently of transcript persistence.
    _applyTurnAndPublish({ type: "compaction_done" });
    _applyTurnAndPublish({ type: "turn_end" });
    _publishWorking(false);
    _maybeSendLateAttachSessionSync();
  });

  // Ownership is claimed at session_start and released at session_shutdown.
  // Only the exact owner lease may publish/clear process-global SDK state or
  // tear down relay/mesh resources.
  runtime.registerLifecycle();

  // ── Commands ──────────────────────────────────────────────────────────────
  runtime.ports.commands.register(ownerPi, runtime);

};

export default extension;

function createRuntimePorts(): OutpostPiRuntimePorts {
  return {
    relay: {
      status: _relayStatus,
      start: (input) => {
        _ensureOwnerIngressListener();
        return _relayTransport.start({
          ...input,
          keypair: input.keypair ?? _pairingCoordinator.currentKeypair() ?? undefined,
          isDisposed: () => _disposed,
          onUnexpectedClose: () => _onRelayClose(),
        });
      },
      stop: (reason) => _goIdle(reason),
      sendRoomMeta: (patch) => {
        _publishRoomMetaPatch({
          session_id: patch.session_id,
          model: patch.model,
          thinking: patch.thinking as ThinkingLevel | undefined,
          working: patch.working,
        });
      },
      onOuterMessage: (handler) => _relayTransport.onOuterMessage(handler),
      createPeerChannel: (input) => _relayTransport.createPeerChannel(input),
      subscribePresence: (peers) => _relayTransport.subscribePresence(peers),
      attachCrossPcBridge: (input) => _relayTransport.attachCrossPcBridge(input),
      detachCrossPcBridge: () => { _relayTransport.detachCrossPcBridge(); },
    },
    owners: {
      activeCount: () => _owners.activeCount(),
      attach: (input) => {
        const channel = _owners.attach({
          ...input,
          roomId: input.roomId ?? _myRoomId ?? undefined,
          turnActive: _turnProjection().working,
        });
        _sdkSessionProjection.recordOwnerAttached(input.peerId);
        _syncOwnerPresenceSubscription();
        return channel;
      },
      detach: (peerId, reason) => {
        const outboundSettled = _owners.detach(peerId, reason);
        _syncOwnerPresenceSubscription();
        return outboundSettled;
      },
      broadcast: (message) => _owners.broadcast(message),
      completeOfflineTurn: () => _owners.completeOfflineTurn(),
      routeFrom: (sender, message) => _owners.routeFrom(sender, message),
      lateAttachTargets: () => _owners.lateAttachTargets(),
    },
    session: {
      bindApi: (boundPi) => {
        _replaceCaptureUploadHandler();
        _pi = boundPi;
        _messageApi = boundPi;
        _sdkSessionProjection.bindApi(boundPi);
        _drainPendingDeliveryQueue();
      },
      onSessionStart: _writeRuntimeIdentity,
      bindCommandContext: _rememberCommandCtx,
      bindSessionContext: (ctx) => {
        // The runtime coordinator is the single ownership authority. A real
        // child/satellite is denied during activation and returns before this
        // port is called, so every context reaching here belongs to the
        // approved owner and must be captured fully. `subagentGate` remains
        // content-suppression evidence only; using it here would suppress a
        // legitimate successor that starts while a subagent tool is open.
        _lastEventCtx = ctx;
        _sdkSessionProjection.bindSessionContext(ctx);
        _captureRemoteSession(ctx);
      },
      clearStaleContexts: (reason) => {
        // Replacement gaps preserve bounded ingress; the successor owner's
        // bindApi drains it exactly once. A terminal quit has no successor.
        if (reason === "quit" && _pendingDeliveryQueue.length > 0) {
          _failPendingDeliveryQueue("session closed before queued message replayed");
        }
        _sdkSessionProjection.clearStaleContexts();
        _lastCtx = null;
        _lastEventCtx = null;
        _messageApi = null;
        _pi = null;
      },
      markAgentRunStarted: () => _sdkSessionProjection.markAgentRunStarted(),
      markAgentSettled: () => _sdkSessionProjection.markAgentSettled(),
      enqueueMeshMessage: (peerId, content) => _sdkSessionProjection.enqueueMeshMessage(peerId, content),
      sendPiMessage: (...args) => _sendPiMessage(...args),
      wakeAgent: (...args) => _sdkSessionProjection.wakeAgent(...args),
      publishWorking: _publishWorking,
      resetTurnSnapshot: () => _sdkSessionProjection.resetTurnSnapshot(),
      handleClientMessage: (sender, message) => _sdkSessionProjection.handleClientMessage(sender, message),
      onSessionLifecycle: (reason: string, sessionIdTail: string) => {
        _deliveryDebugLog.log({
          tag: "session_lifecycle",
          reason: reason as "startup" | "reload" | "new" | "resume" | "fork" | "quit",
          sessionIdTail,
          roomId: _myRoomId ?? undefined,
        });
      },
    } as OutpostPiRuntimePorts["session"],
    commands: {
      register: (boundPi, runtime) => {
        if ((boundPi as ExtensionAPI & { __outpostPiTestHarness?: boolean })
              .__outpostPiTestHarness === true) {
          _freshSessionShutdown.resetForTest();
        }
        if (runtime.isOwner()) _activeOutpostPiRuntime = runtime;
        createRuntimeCommandSurface().register(boundPi, runtime);
      },
      activateRuntime: (runtime) => { _activeOutpostPiRuntime = runtime; },
      ensureStarted: (ctx) => {
        // Auto-start when the relay is not yet connected on this process —
        // covers both a fresh process (_state="idle", _disposed=false) and a
        // post-replacement restart (_disposed=true). Skip only if already
        // started, preventing double-start on repeated session_start events.
        // Without this, a fresh pi process (including after a hot-reload
        // restart) never auto-connects the relay.
        if (_state === "started") return;
        _disposed = false;
        _startRootInBackground(ctx, "session-start");
      },
      prepareSessionShutdown: () => {
        _disposed = true;
        _disposeCaptureUploadHandler();
      },
      closeMesh: async () => {
        if (_meshNode) {
          try { await _meshNode.close(); } catch { /* best-effort */ }
          _meshNode = null;
          _owners.setMeshSession(null);
          _owners.setSessionPeerCount(0);
        }
        _localMeshCommands.releaseCwdLock();
      },
    },
  };
}

function createRuntimeCommandSurface(): CommandSurfacePort {
  return createCommandSurface({
    deployAgentNetworkSkill: _deployAgentNetworkSkill,
    refreshPairingsCache: () => { void _owners.refreshPairingsCache(); },
    registerAgentTools: (pi) => registerAgentTools(pi, () => _meshNode?.peer() ?? null),
    registerCommands: _registerOutpostPiCommands,
    startDaemonMode: _startDaemonMode,
  });
}

function _rememberCommandCtx(ctx: ExtensionCommandContext): void {
  _lastCtx = ctx;
  _sdkSessionProjection.bindCommandContext(ctx);
}

function _bindReplacementSessionContext(freshCtx: ActionCtx): void {
  _lastCtx = freshCtx as unknown as typeof _lastCtx;
  _lastEventCtx = freshCtx as unknown as typeof _lastEventCtx;
  _pi = null;
  _sdkSessionProjection.bindReplacementContext(freshCtx);
  _messageApi = _sdkSessionProjection.messageApiBinding();
  // Drain any inbound messages queued during the null window — mirrors the
  // factory `bindApi` drain. `session_new` (the mobile quick-action) re-arms
  // through this path via `withSession`, so this is the mobile-lockout
  // recovery drain. Without it, a message queued during a `session_new`-
  // driven replacement would sit until TTL → `internal_error` despite a
  // valid message API now being available.
  // See story-fix-stale-ctx-messageapi-rearm-on-reload review finding.
  _drainPendingDeliveryQueue();
}

function _registerOutpostPiCommands(pi: ExtensionAPI): void {
  const runWithCtx = (
    run: (args: string, ctx: ExtensionCommandContext) => void | Promise<void>,
  ) => async (args: string, ctx: ExtensionCommandContext) => {
    _rememberCommandCtx(ctx);
    return run(args, _safeCommandContext(ctx));
  };

  const specs: OutpostPiCommandSpec[] = [
    { suffix: "setup", description: "Run the setup wizard and update local config", run: runWithCtx(async (_args, ctx) => { await _cmdSetup(ctx); }) },
    { suffix: "hot-reload", description: "Manage process-restart hot reload: on, off, arm, or status", run: runWithCtx((args, ctx) => { _cmdHotReload(args, ctx); }) },
    { suffix: "status", description: "Show local mesh + relay status", run: runWithCtx((_args, ctx) => { _cmdStatus(ctx); }) },
    { suffix: "stop", description: "Stop everything (leave local mesh + disconnect relay)", run: runWithCtx(async (_args, ctx) => { await _cmdStop(ctx); }) },
    { suffix: "pair", description: "Show a QR code to pair a new mobile device (optional: --ttl <seconds>)", run: runWithCtx(async (args, ctx) => { await _cmdPair(ctx, args); }) },
    { suffix: "devices", description: "List paired mobile devices", run: runWithCtx(async (_args, ctx) => { await _cmdList(ctx); }) },
    { suffix: "revoke", description: "Revoke a paired device by its shortid", complete: async (prefix) => _shortidCompletions(prefix), run: runWithCtx(async (args, ctx) => { await _cmdRevoke(args, ctx); }) },
    { suffix: "set-relay", description: "Persist a new relay URL to user config", run: runWithCtx((args, ctx) => { _cmdSetRelay(args, ctx); }) },
    { suffix: "peers", description: "List local + cross-PC mesh peers, grouped by PC label", run: runWithCtx(async (_args, ctx) => { await _cmdPeers(ctx); }) },
    { suffix: "create", description: "Register a folder as a daemon and start it (when the supervisor is running)", run: runWithCtx(async (args, ctx) => { await _daemonCommands.create(args, ctx); }) },
    { suffix: "remove", description: "Stop + unregister a daemon by id (local config is preserved)", run: runWithCtx(async (args, ctx) => { await _daemonCommands.remove(args, ctx); }) },
    { suffix: "daemons", description: "List registered daemons + state", run: runWithCtx(async (_args, ctx) => { await _daemonCommands.list(ctx); }) },
    { suffix: "daemon start", description: "Start daemons: all, or one by id (`daemon start <id>`)", run: runWithCtx(async (args, ctx) => { await _daemonCommands.start(ctx, args || undefined); }) },
    { suffix: "daemon stop", description: "Stop daemons: all, or one by id (`daemon stop <id>`)", run: runWithCtx(async (args, ctx) => { await _daemonCommands.stop(ctx, args || undefined); }) },
    { suffix: "daemon restart", description: "Restart daemons: all, or one by id (`daemon restart <id>`)", run: runWithCtx(async (args, ctx) => { await _daemonCommands.restart(ctx, args || undefined); }) },
    { suffix: "daemon status", description: "Show fleet runtime status (pid, uptime, restarts)", run: runWithCtx(async (_args, ctx) => { await _daemonCommands.status(ctx); }) },
    { suffix: "daemon send", description: "Send a prompt to a daemon: `daemon send <id> \"<text>\"`", run: runWithCtx(async (args, ctx) => { await _daemonCommands.send(args, ctx); }) },
    { suffix: "cron", completionValues: ["cron", "cron add", "cron list", "cron remove", "cron enable", "cron disable", "cron run", "cron log"], description: "Schedule recurring prompts to daemons: `cron <add|list|remove|enable|disable|run|log>`", run: runWithCtx(async (args, ctx) => { await _cronCommands.run(args, ctx); }) },
    { suffix: "install", description: "Install pi-supervisord as a system service + link the outpost-pi CLI (systemd/launchd/Task Scheduler; Windows prompts for admin)", run: runWithCtx((_args, ctx) => { _serviceCommands.install(ctx, { linkCli: true }); }) },
    { suffix: "uninstall", description: "Remove the pi-supervisord system service + the CLI shims (daemons registry preserved; Windows prompts for admin)", run: runWithCtx((_args, ctx) => { _serviceCommands.uninstall(ctx, { linkCli: true }); }) },
  ];

  registerOutpostPiCommands(
    pi,
    specs,
    async (sub, ctx) => {
      _rememberCommandCtx(ctx);
      const safeCtx = _safeCommandContext(ctx);
      const spec = specs
        .slice()
        .sort((a, b) => b.suffix.length - a.suffix.length)
        .find((candidate) => sub === candidate.suffix || sub.startsWith(`${candidate.suffix} `));
      if (!spec) {
        await _cmdRoot(safeCtx);
        return;
      }
      const args = sub === spec.suffix ? "" : sub.slice(spec.suffix.length).trim();
      await spec.run(args, safeCtx);
    },
  );
}

function _startDaemonMode(): void {
  const daemonCtx = {
    ui: _headlessUi(),
    cwd: process.cwd(),
  } as unknown as Pick<ExtensionContext, "ui" | "cwd">;
  setTimeout(() => { _startRootInBackground(daemonCtx, "daemon-start"); }, 0);
}

const _localMeshCommands = new LocalMeshCommands({
  isDisposed: () => _disposed,
  getState: getStateForTest,
  meshNode: () => _meshNode,
  setMeshNode: (node) => { _meshNode = node; },
  setSessionState: (sessionName, peerCount) => {
    _owners.setMeshSession(sessionName);
    _owners.setSessionPeerCount(peerCount);
  },
  startRelay: _cmdStart,
  stopRelay: _goIdle,
  status: _cmdStatus,
  controlCtx: _controlCtx,
  emitRelayState: _emitRelayState,
  refreshFooter: _refreshFooter,
  refreshSessionPeerCount: _refreshSessionPeerCount,
  deliverMeshMessage: _deliverMeshMessageToAgent,
  attachBridgeIfReady: _attachBridgeIfReady,
  notify: _notify,
  sendPiMessage: _sendPiMessage,
});

// ── Command implementations ───────────────────────────────────────────────────

/**
 * `/outpost-pi status` — full state snapshot. Two lines: local mesh + relay.
 *
 * Always callable; safe when nothing is up (renders the off variants).
 * Reuses the same icons as the footer so terminal + status output stay
 * visually consistent.
 */
function _cmdStatus(ctx: Pick<ExtensionContext, "ui">): void {
  const relayUrl = _relayTransport.currentRelayUrl() ?? resolveRelayUrl().url;
  const ownerSnapshot = _owners.snapshot();

  // Mesh line
  let meshLine: string;
  if (_meshNode) {
    const name = _meshNode.name();
    const count = ownerSnapshot.sessionPeerCount;
    meshLine = `🟢 Local mesh: connected as "${name}" (${count} peer${count === 1 ? "" : "s"})`;
  } else {
    meshLine = "⚪ Local mesh: not connected";
  }

  // Relay line — paired state is derived from OwnerMultiplexer snapshot.
  let relayLine: string;
  if (relayUrl === null) {
    relayLine = "⚪ Relay: unconfigured — run /outpost-pi set-relay <url>";
  } else if (_state === "idle") {
    relayLine = `⚪ Relay: off (${relayUrl}) — run /outpost-pi to start`;
  } else if (ownerSnapshot.activeOwnerCount > 0) {
    const count = ownerSnapshot.activeOwnerCount;
    const shortids = ownerSnapshot.ownerShortIds.join(", ");
    relayLine = `🟢 Relay: ${count} owner${count === 1 ? "" : "s"} online (${shortids}) (${relayUrl})`;
  } else {
    relayLine = ownerSnapshot.hasGlobalPairings
      ? `🟢 Relay: on, waiting for an app to connect (${relayUrl})`
      : `🟡 Relay: on, waiting for first pairing (${relayUrl})`;
  }

  _notify(`[outpost-pi]\n  ${meshLine}\n  ${relayLine}`, "info", ctx);
}

async function _cmdPeers(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  await _localMeshCommands.peers(_safeCommandContext(ctx));
}

/** Start the local mesh root in the background and consume its failure at this boundary. */
function _startRootInBackground(
  ctx: Pick<ExtensionContext, "ui" | "cwd">,
  origin: "session-start" | "daemon-start" | "session-replacement",
): void {
  void _cmdRoot(ctx).catch((error: unknown) => {
    console.error(`[outpost-pi] ${origin} auto-start failed: ${String(error)}`);
  });
}

async function _cmdRoot(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  await _localMeshCommands.root(_safeCommandContext(ctx));
}

async function _cmdSetup(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  await _localMeshCommands.setup(_safeCommandContext(ctx));
}

// The pair command can race the relay start directly (pair during the
// fire-and-forget session-start auto-start), below any root-level guard.
let _relayStartInFlight: Promise<void> | null = null;

async function _startRelayViaTransport(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  ctx = _safeCommandContext(ctx);
  if (_state !== "idle") {
    ctx.ui.notify("[outpost-pi] Already started.", "warning");
    return;
  }
  // A concurrent start passes the idle check above because `_state` flips only
  // after the first connect resolves. Converge onto the in-flight start
  // instead of opening a second relay connection whose supersede-close
  // (unbind-then-close) silently kills frames routed to the loser.
  if (_relayStartInFlight) return _relayStartInFlight;
  const run = _startRelayViaTransportInner(ctx);
  _relayStartInFlight = run.finally(() => { _relayStartInFlight = null; });
  return _relayStartInFlight;
}

async function _startRelayViaTransportInner(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  const relayResolution = resolveRelayUrl();
  if (relayResolution.source === "unconfigured") {
    ctx.ui.notify(
      "[outpost-pi] Relay not configured. Run /outpost-pi set-relay <url> and try again.",
      "warning",
    );
    return;
  }
  const { url: relayUrl, source } = relayResolution;

  let edKp: Ed25519Keypair;
  try {
    edKp = await getOrCreateEd25519Keypair();
  } catch (err) {
    if (err instanceof KeyringUnavailableError) {
      ctx.ui.notify(
        "[outpost-pi] Could not read this machine's identity: the system " +
        "keychain is locked or access was denied. Unlock it (open the app / " +
        "log in) and run /outpost-pi again. Your pairing is NOT lost. " +
        "(Set OUTPOST_PI_ALLOW_FILE_IDENTITY=1 only for headless hosts.)",
        "error",
      );
      return;
    }
    if (err instanceof PairedIdentityMissingError) {
      ctx.ui.notify(
        "[outpost-pi] Could not read this machine's identity, but devices are " +
        "already paired. Refusing to generate a replacement that would revoke " +
        "them. Give this process access to the original keyring, or install the " +
        "original keypair at ~/.pi/remote/identity.json with mode 0600.",
        "error",
      );
      return;
    }
    throw err;
  }
  _pairingCoordinator.recordCurrentKeypair(edKp);

  const myShort = Buffer.from(edKp.publicKey).toString("base64").slice(0, 8);
  const cwd = "cwd" in ctx && typeof ctx.cwd === "string" ? ctx.cwd : process.cwd();
  const sessionName = _displayName(cwd);
  const roomId = roomIdFor(cwd, sessionName);

  if (!_currentModelName()) {
    try {
      const c = ctx as Partial<ExtensionContext> & {
        model?: { name?: string; id?: string };
        getModel?: () => { name?: string; id?: string } | undefined;
      };
      const live = c.getModel?.() ?? c.model;
      if (live) {
        _currentModel = live.name ?? live.id ?? undefined;
      } else {
        const sm = SettingsManager.create(cwd);
        const provider = sm.getDefaultProvider();
        const modelId = sm.getDefaultModel();
        if (modelId) {
          const found = provider ? ensureModelRegistry().find(provider, modelId) : undefined;
          _currentModel = found?.name ?? modelId;
        }
      }
    } catch { /* defensive — never block start on a model lookup */ }
  }

  try {
    _currentThinking = _pi?.getThinkingLevel() as ThinkingLevel | undefined;
  } catch { /* defensive — never block /outpost-pi start on this */ }

  const sessionId = _currentRemoteSessionId(ctx);
  const roomMeta = { name: sessionName, cwd, session_id: sessionId } as NonNullable<typeof _myRoomMeta>;
  const modelName = _currentModelName();
  if (modelName) roomMeta.model = modelName;
  if (_currentThinking) roomMeta.thinking = _currentThinking;
  _myRoomMeta = roomMeta;

  ctx.ui.notify(`[outpost-pi] Connecting to relay ${relayUrl} (source: ${source}, room: ${roomId})…`, "info");

  try {
    _ensureOwnerIngressListener();
    await _relayTransport.start({
      relayUrl,
      keypair: edKp,
      roomId,
      roomMeta,
      isDisposed: () => _disposed,
      onUnexpectedClose: () => _onRelayClose(),
      // On every (re)connect, republish the AUTHORITATIVE working state rather
      // than an unconditional false. This clears stale working=true left by a
      // killed predecessor (whose successor starts idle → projection false)
      // WITHOUT clobbering a genuine working=true if the relay drops and
      // reconnects mid-turn (a transient network blip during a live turn).
      // session_start publishes too, but it fires before the relay connects
      // (the transport starts later via _startRelayViaTransport), so that
      // publish is a no-op on a fresh process. This callback covers both the
      // initial connect and subsequent reconnects after a relay drop.
      onConnected: () => {
        _sdkSessionProjection.publishWorking(_turnProjection().working);
      },
    });
  } catch (err) {
    if (err instanceof RelayStartAbortedError) return;
    if (err instanceof RoomAlreadyOpenError) {
      ctx.ui.notify(
        "[outpost-pi] Already running in this cwd. Stop the other terminal first.",
        "error",
      );
      return;
    }
    _notify(`[outpost-pi] relay connect failed: ${String(err)}`, "error", ctx);
    return;
  }

  _myRoomId = roomId;
  _sdkSessionProjection.setRoomId(roomId);
  _state = "started";
  _sdkSessionProjection.ensureSessionStarted();
  _refreshFooter(ctx);

  _pairingCoordinator.startSelfRevoke(relayUrl, edKp);
  _attachBridgeIfReady();
  _emitRelayState();
  ctx.ui.notify(`[outpost-pi] state: started (peer=${myShort}) — Connected to relay ${relayUrl}`, "info");
}

async function _cmdStart(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  await _startRelayViaTransport(ctx);
}

/**
 * `/outpost-pi pair` — always generates a fresh QR when the relay is up.
 *
 * The coordinator owns QR token issuance and relay-dependent command policy;
 * transport/owner ports route known-peer reconnect and pair_request handling
 * through owner/session ports instead of mutating index state directly.
 */
async function _cmdPair(ctx: Pick<ExtensionContext, "ui" | "cwd">, args = ""): Promise<void> {
  await _pairingCommands.pair(_safeCommandContext(ctx), args);
}

async function _cmdStop(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  await _localMeshCommands.stop(_safeCommandContext(ctx));
}

async function _cmdList(ctx: Pick<ExtensionContext, "ui">): Promise<void> {
  await _pairingCommands.devices(_safeCommandContext(ctx));
}

async function _cmdRevoke(arg: string, ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  await _pairingCommands.revoke(arg, _safeCommandContext(ctx));
}

async function _shortidCompletions(
  prefix: string,
  valuePrefix = "",
): Promise<Array<{ value: string; label: string }>> {
  return _pairingCommands.completeShortid(prefix, valuePrefix);
}

function _cmdSetRelay(arg: string, ctx: Pick<ExtensionContext, "ui">): void {
  _relayCommands.setRelay(arg, ctx);
}

// Daemon, cron, and service command handlers live in extension/command_surface/*.
// The daemon/ modules remain the single source of runtime behavior.

// ── Agent-network commands (Plan 19) ──────────────────────────────────────────

function _resolveExtensionDir(): string {
  // dist/index.js → dist; skills sit at <extensionRoot>/skills/. When we run
  // from src/ via tsx (dev), index.ts is in src/ and skills/ is sibling. We
  // detect by checking both locations.
  const here = fileURLToPath(import.meta.url);
  // dist/index.js or src/index.ts → parent = <dist or src>; sibling = ../skills
  const parent = here.replace(/\/[^/]+$/, "");
  const candidateA = join(parent, "..", "skills"); // dist → ../skills
  const candidateB = join(parent, "skills");        // src → skills
  if (existsSync(candidateA)) return parent.replace(/\/dist$/, "");
  if (existsSync(candidateB)) return parent;
  return parent;
}

function _deployAgentNetworkSkill(): void {
  // Pi SDK spec (core/skills.js): every skill must live at
  //   <skillsRoot>/<skill-name>/SKILL.md
  // The skill `name:` frontmatter must equal the parent directory name. We
  // ship the source pre-arranged that way so deploy is a straight copy into
  // ~/.pi/remote/skills/agent-network/SKILL.md.
  const root = _resolveExtensionDir();
  const src1 = join(root, "skills", "agent-network", "SKILL.md");
  const src2 = join(root, "..", "skills", "agent-network", "SKILL.md");
  const src = existsSync(src1) ? src1 : (existsSync(src2) ? src2 : null);
  if (!src) return;
  const dstDir = join(skillsDir(), "agent-network");
  const dst = join(dstDir, "SKILL.md");
  try {
    mkdirSync(dstDir, { recursive: true });
    copyFileSync(src, dst);
    // Cleanup legacy deploy at ~/.pi/remote/skills/agent-network.md (flat
    // layout, fails the Pi SDK's name-vs-parent-dir validation).
    const legacy = join(skillsDir(), "agent-network.md");
    if (existsSync(legacy)) {
      try { unlinkSync(legacy); } catch { /* ignored */ }
    }
  } catch { /* best-effort */ }
}

/**
 * Inject text into the agent as a user message, waking a turn. The base
 * `ExtensionAPI.sendUserMessage` is synchronous, while replacement-session
 * contexts can return a Promise; this helper handles both and treats a rejected
 * handoff as a failed delivery. The SDK runtime still owns any later turn
 * failure (no model/API key, expired auth, provider error), which surfaces in
 * the agent's own output, not back to us. Two gaps this helper closes, both of
 * which previously failed silently:
 *
 *   1. `_pi` not bound yet (activation race / mesh joined before the session
 *      attached): the old code did `if (!_pi) return`, dropping the message
 *      with no trace. We log it (the daemon forwards child stderr to its log
 *      with a cwd prefix, so it's visible in `journalctl`).
 *   2. A synchronous throw or Promise rejection from `sendUserMessage` (e.g.
 *      malformed content or a stale replacement context): the old fire-and-
 *      forget call could either propagate out of the `onMessage` callback or
 *      create a false success echo. We catch + surface it instead.
 *
 * NOTE: this does NOT make a wake that fails *inside* the SDK observable —
 * that requires a fix in the Pi runtime (no extension-level error event
 * exists for it). See `.orchestration/results/mesh-liveness-stale-peer.md`.
 */
type SendUserMessageOptions =
  NonNullable<Parameters<ExtensionAPI["sendUserMessage"]>[1]>;

async function _wakeAgent(
  content: Parameters<ExtensionAPI["sendUserMessage"]>[0],
  label: string,
  steeringBehavior?: SendUserMessageOptions["deliverAs"],
): Promise<WakeAgentResult> {
  const wake = steeringBehavior
    ? await _sdkSessionProjection.wakeAgent(content, { deliverAs: steeringBehavior })
    : await _sdkSessionProjection.wakeAgent(content);
  if (!wake.ok) {
    const detail = wake.detail ?? "agent session not bound yet";
    if (wake.recoverable) return wake;
    console.error(`[outpost-pi] ${label}: agent rejected incoming message: ${detail}`);
    _notify(`[outpost-pi] failed to process incoming message: ${detail}`, "error");
    return wake;
  }
  return wake;
}

/**
 * Deliver an inbound agent-network (mesh) message to the agent + the app.
 *
 * Display: the app renders it in the TOOL timeline (a matched
 * tool_request/tool_result "agent-network" pair) — NOT as the user's own
 * message, which is what `sendUserMessage` used to produce (the reported bug).
 *
 * Wake: we inject a CUSTOM message (role:"custom"), not a user message. The
 * SDK's `convertToLlm` maps custom → a user-role LLM message, so the agent
 * still sees + replies to it, but `message_end` does NOT buffer role:"custom",
 * so it never replays as `user_input` on session_sync. Ingress is admitted
 * under frame and byte limits, retained while an agent run is active, and
 * flushed as one custom batch with one turn trigger at `agent_settled`.
 * `id` lets the LLM echo it via `agent_send(..., re=<id>)`.
 */
function _deliverMeshMessageToAgent(
  env: { id: string; from: string; re: string | null; body: unknown },
): void {
  const bodyText = typeof env.body === "string" ? env.body : (JSON.stringify(env.body) ?? "null");
  const header = `[agent-network] message from "${env.from}" (id=${env.id}${env.re ? `, re=${env.re}` : ""}):`;
  const footer = env.re
    ? "(This is a reply to a previous message of yours.)"
    : `(If a reply is expected, call agent_send with to="${env.from}" and re="${env.id}".)`;
  const admission = _sdkSessionProjection.enqueueMeshMessage(
    env.from,
    `${header}\n${bodyText}\n\n${footer}`,
  );
  if (!admission.accepted) {
    console.error(`[outpost-pi] mesh ingress rejected: ${admission.reason}`);
    _notify("[outpost-pi] incoming mesh queue is full; message was not delivered", "error");
    return;
  }

  const toolCallId = `mesh_${env.id}`;
  const sessionId = _currentRemoteSessionId();
  const args = env.re
    ? { from: env.from, re: env.re, message: bodyText }
    : { from: env.from, message: bodyText };
  const requestEventId = deterministicTranscriptEventId(sessionId, "tool_requested", toolCallId);
  const requestTs = _sdkSessionProjection.recordedTranscriptTs(requestEventId) ?? Date.now();
  const requestRecorded = _recordDurableTranscriptEvent({
    kind: "tool_requested",
    eventId: requestEventId,
    sessionId,
    ts: requestTs,
    toolCallId,
    tool: "agent-network",
    args,
  });
  if (!_isAuthoritativeTranscriptRecord(requestRecorded)) return;

  const finishEventId = deterministicTranscriptEventId(sessionId, "tool_finished", toolCallId);
  const finishTs = _sdkSessionProjection.recordedTranscriptTs(finishEventId) ?? Date.now();
  const finishResult = { from: env.from, message: bodyText };
  let finishRecorded = _recordDurableTranscriptEvent({
    kind: "tool_finished",
    eventId: finishEventId,
    sessionId,
    ts: finishTs,
    toolCallId,
    result: finishResult,
  });
  let finishError: string | undefined;
  if (!_isAuthoritativeTranscriptRecord(finishRecorded)) {
    finishError = "mesh transcript result persistence failed";
    finishRecorded = _recordDurableTranscriptEvent({
      kind: "tool_finished",
      eventId: finishEventId,
      sessionId,
      ts: finishTs,
      toolCallId,
      error: finishError,
    });
  }
  if (!_isAuthoritativeTranscriptRecord(finishRecorded)) return;

  _owners.broadcast(_withCurrentSession({
    type: "tool_request",
    tool_call_id: toolCallId,
    tool: "agent-network",
    args,
    ts: requestTs,
  }));
  _owners.broadcast(_withCurrentSession(finishError
    ? {
        type: "tool_result",
        tool_call_id: toolCallId,
        error: finishError,
        ts: finishTs,
      }
    : {
        type: "tool_result",
        tool_call_id: toolCallId,
        result: finishResult,
        ts: finishTs,
      }));
}

/** Test-only seam for producer-connected native mesh transcript coverage. */
export function _deliverMeshMessageToAgentForTest(
  env: { id: string; from: string; re: string | null; body: unknown },
): void {
  _deliverMeshMessageToAgent(env);
}

async function _cmdJoin(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> {
  await _localMeshCommands.join(ctx);
}

// ── routeClientMessage ────────────────────────────────────────────────────────

/**
 * Per-channel router. Replaces the W2D-pre `routeClientMessage` which
 * implicitly used the `_peerChannel` singleton for replies. Each managed
 * owner channel now carries its own `sender` and passes it here so
 * sender-specific responses (cancelled, pong, session_history) flow back
 * through the right wire instead of being broadcast.
 *
 * Broadcast messages (user_input mirror, agent_chunk, and SDK-originated
 * tool_*) still fan out through OwnerMultiplexer; the agent-network delivery
 * helper also emits its own tool_request/tool_result pair. This router only
 * handles incoming app→pi requests.
 */
function _abortCurrentTurn(
  fallbackCtx?: Pick<ExtensionContext, "abort">,
): boolean {
  const candidates: Array<Pick<ExtensionContext, "abort"> | null | undefined> = [
    _lastEventCtx,
    _lastCtx,
    fallbackCtx,
  ];

  for (const candidate of candidates) {
    if (!candidate || candidate === _noopCtx) continue;
    if (typeof candidate.abort !== "function") continue;
    try {
      candidate.abort();
      return true;
    } catch (err) {
      if (!_isStaleContextError(err)) throw err;
      if (candidate === _lastCtx) _lastCtx = null;
      if (candidate === _lastEventCtx) _lastEventCtx = null;
      _sdkSessionProjection.forgetStaleBinding(candidate);
    }
  }

  return false;
}

type UserClientMessage = Extract<ClientMessage, { type: "user_message" }>;

type PreparedUserDelivery = {
  sender: PlainPeerChannel | null;
  msg: UserClientMessage;
  content: Parameters<ExtensionAPI["sendUserMessage"]>[0];
  shouldSteer: boolean;
  source: "app" | "queued";
  label: string;
};

type PendingDeliveryEntry = PreparedUserDelivery & {
  queueId: number;
  enqueuedAt: number;
  timeout: ReturnType<typeof setTimeout>;
};

const kPendingDeliveryQueueMax = 2;
let _pendingDeliveryTtlMs = 5_000;
/** Absolute cap on how long a queued message waits across renewals during a
 *  slow/stuck replacement, after which it expires to `internal_error` even
 *  while `REPLACING`. Bounds the renew loop so a replacement whose successor
 *  creation failed (SDK propagates the error; RPC mode stays alive) cannot
 *  renew a queued message forever. Matches the app-side
 *  `deliveryPendingEchoTimeout` (60s) fallback so both sides give up together. */
const kPendingDeliveryAbsoluteDeadlineMs = 60_000;
let _pendingDeliveryAbsoluteDeadlineMs = kPendingDeliveryAbsoluteDeadlineMs;
let _pendingDeliveryQueue: PendingDeliveryEntry[] = [];
let _nextPendingDeliveryQueueId = 1;

/** In-flight user-message delivery attempts, keyed by `${sessionId}:${msg.id}`
 *  (story-extension-user-message-ingress-idempotency). A duplicate frame that
 *  arrives while the first attempt is pending coalesces onto the same promise
 *  (no second `_wakeAgent`). On success the id is recorded as delivered, so a
 *  later duplicate is suppressed + re-echoed without waking. On failure the
 *  entry is released so a replay-queue re-attempt can retry. */
const _inflightUserDeliveries = new Map<string, Promise<WakeAgentResult>>();

const kFreshSessionShutdownDeadlineMs = 10_000;
function _isFreshSessionRestartManaged(): boolean {
  return process.env["OUTPOST_PI_DAEMON"] === "1"
    || process.env["OUTPOST_PI_UNDER_RESTART_WRAPPER"] === "1";
}

const _freshSessionShutdown = new FreshSessionShutdownCoordinator({
  isRestartManaged: _isFreshSessionRestartManaged,
  drainAcceptedDeliveries: async () => {
    while (_inflightUserDeliveries.size > 0) {
      await Promise.allSettled([..._inflightUserDeliveries.values()]);
    }
  },
  terminate: (exitCode) => { process.exit(exitCode); },
  shutdownDeadlineMs: kFreshSessionShutdownDeadlineMs,
  exitCode: EXIT_FRESH_SESSION,
});

/** @internal test override for the pending-delivery TTL. */
export function _setPendingDeliveryTtlForTest(ms: number): () => void {
  _pendingDeliveryTtlMs = ms;
  return () => { _pendingDeliveryTtlMs = 5_000; };
}

/** @internal test override for the absolute renewal deadline. */
export function _setPendingDeliveryAbsoluteDeadlineForTest(ms: number): () => void {
  _pendingDeliveryAbsoluteDeadlineMs = ms;
  return () => { _pendingDeliveryAbsoluteDeadlineMs = kPendingDeliveryAbsoluteDeadlineMs; };
}

function _sendDeliveryError(sender: PlainPeerChannel | null, inReplyTo: string, detail: string): void {
  _sendRenderableTranscriptError(
    sender,
    "internal_error",
    `Agent rejected incoming message: ${detail}`,
    inReplyTo,
  );
}

function _sendDeliveryPending(sender: PlainPeerChannel | null, inReplyTo: string): void {
  const pending: ServerMessage = _withCurrentSession({
    type: "error",
    code: "delivery_pending",
    in_reply_to: inReplyTo,
    message: "session replacing — message queued for replay",
  });
  if (sender) sender.send(pending);
  else _owners.broadcast(pending);
}

function _sendDeliveryRetry(
  sender: PlainPeerChannel | null,
  inReplyTo: string,
  reason: "hot_reload" | "fresh_session",
): void {
  const retry: ServerMessage = _withCurrentSession({
    type: "error",
    code: "delivery_retry",
    in_reply_to: inReplyTo,
    message: reason === "fresh_session"
      ? "fresh session shutdown is in progress; retry after room recovery"
      : "extension hot-reload is in progress; retry after room recovery",
  });
  if (sender) sender.send(retry);
  else _owners.broadcast(retry);
}

function _prepareUserDelivery(
  msg: UserClientMessage,
  sender: PlainPeerChannel | null,
  mode: "auto" | "normal",
): PreparedUserDelivery {
  const requestedSteer = mode === "auto" && msg.streaming_behavior === "steer";
  const inferredBusySteer = mode === "auto" && !requestedSteer && _myRoomMeta?.working === true;
  const shouldSteer = requestedSteer || inferredBusySteer;
  const content: Parameters<ExtensionAPI["sendUserMessage"]>[0] =
    msg.images && msg.images.length > 0
      ? [
          ...msg.images.map((img) => ({ type: "image" as const, data: img.data, mimeType: img.mime })),
          { type: "text" as const, text: msg.text },
        ]
      : msg.text;
  return {
    sender,
    msg,
    content,
    shouldSteer,
    source: mode === "normal" ? "queued" : "app",
    label: msg.images && msg.images.length > 0
      ? `app user_message id=${msg.id} (+${msg.images.length} image)`
      : `app user_message id=${msg.id}`,
  };
}

async function _attemptUserDelivery(prepared: PreparedUserDelivery): Promise<WakeAgentResult> {
  // Ingress idempotency coordinator (story-extension-user-message-ingress-
  // idempotency). Capture the session id at attempt time (not at record time)
  // so a replacement mid-attempt doesn't misattribute the delivery.
  const attemptSessionId = _currentRemoteSessionId();
  const dedupeKey = `${attemptSessionId}:${prepared.msg.id}`;

  // Already delivered? Suppress + re-echo (idempotent confirmation) without
  // re-invoking the agent. Covers sequential duplicates (reconnect flush,
  // relay fan-out, app re-send) that arrive after the first attempt succeeded.
  if (_sdkSessionProjection.wasUserMessageDelivered(attemptSessionId, prepared.msg.id)) {
    const eventId = deterministicTranscriptEventId(attemptSessionId, "user_confirmed", prepared.msg.id);
    const ts = _sdkSessionProjection.recordedTranscriptTs(eventId);
    const echo: ServerMessage = _withCurrentSession({
      type: "user_message",
      id: prepared.msg.id,
      text: prepared.msg.text,
      ...(prepared.msg.images && prepared.msg.images.length > 0 ? { images: prepared.msg.images } : {}),
      ...(prepared.shouldSteer ? { streaming_behavior: "steer" as const } : {}),
      ...(ts !== undefined ? { ts } : {}),
    });
    _owners.broadcast(echo);
    _deliveryDebugLog.log({
      tag: "ingress_dedupe",
      id: prepared.msg.id,
      source: prepared.source,
      sessionIdTail: idTail(attemptSessionId),
      roomId: _myRoomId ?? undefined,
    });
    return { ok: true };
  }

  // In-flight? Coalesce onto the existing attempt — a concurrent duplicate
  // awaits the same promise instead of calling _wakeAgent a second time.
  const existing = _inflightUserDeliveries.get(dedupeKey);
  if (existing) return existing;

  const attempt = _attemptUserDeliveryOnce(prepared, attemptSessionId).finally(() => {
    _inflightUserDeliveries.delete(dedupeKey);
  });
  _inflightUserDeliveries.set(dedupeKey, attempt);
  return attempt;
}

async function _attemptUserDeliveryOnce(prepared: PreparedUserDelivery, attemptSessionId: string): Promise<WakeAgentResult> {
  // A reconnecting app can correctly send `steer` while our projection has no
  // turn id (for example, the turn started while no owner was attached).
  // Also be defensive for clients that send a plain user_message while the
  // room is already working. Tell the SDK this is steering; otherwise it
  // rejects the message as a normal busy prompt. Seed the projection so
  // later chunks/done have a target instead of being dropped.
  const turnSeed = _sdkSessionProjection.seedUserMessageTurn({
    turnId: prepared.msg.id,
    source: prepared.source,
    shouldSteer: prepared.shouldSteer,
  });
  const eventId = deterministicTranscriptEventId(attemptSessionId, "user_confirmed", prepared.msg.id);
  const cancelUserEventReservation = _rememberDeliveredUserEvent(
    prepared.msg.text,
    prepared.msg.images,
    prepared.msg.id,
    eventId,
  );
  const rollbackAttempt = () => {
    turnSeed.rollback();
    if (turnSeed.seeded) {
      _applyTurnAndPublish({ type: "delivery_error", turnId: prepared.msg.id });
    }
  };
  let wake: WakeAgentResult;
  try {
    wake = await _wakeAgent(
      prepared.content,
      prepared.label,
      prepared.shouldSteer ? "steer" : undefined,
    );
  } catch (error) {
    cancelUserEventReservation();
    rollbackAttempt();
    throw error;
  }
  // Project the wake failure to a fixed category for the debug log only. The
  // raw `wake.detail` (err.message) can carry prompt/token text from a
  // provider error; persisting it to delivery.log would violate the
  // metadata-only diagnostic contract. The app-facing delivery error
  // (_sendDeliveryError below) keeps its message — this projection is
  // diagnostic-surface-only.
  const wakeDetailCategory = wake.ok
    ? "ok"
    : wake.recoverable
      ? "recoverable_not_bound_or_stale"
      : "send_failed";
  _deliveryDebugLog.log({
    tag: "wake_outcome",
    id: prepared.msg.id,
    ok: wake.ok,
    recoverable: wake.recoverable ?? false,
    detail: wakeDetailCategory,
    messageApiArmed: _sdkSessionProjection.messageApiBinding() !== null,
    roomId: _myRoomId ?? undefined,
  });
  if (!wake.ok) {
    cancelUserEventReservation();
    rollbackAttempt();
    return wake;
  }
  _confirmUserDelivery(prepared.msg, prepared.shouldSteer, attemptSessionId, eventId);
  _deliveryDebugLog.log({
    tag: "msg_delivered",
    id: prepared.msg.id,
    sessionIdTail: idTail(_currentRemoteSessionId()),
    roomId: _myRoomId ?? undefined,
  });
  return wake;
}

function _confirmUserDelivery(
  msg: UserClientMessage,
  shouldSteer: boolean,
  attemptSessionId: string,
  eventId: string,
): void {
  const sessionId = attemptSessionId;
  const producedAt = Date.now();
  const recorded = _recordDurableTranscriptEvent({
    kind: "user_confirmed",
    eventId,
    sessionId,
    ts: producedAt,
    clientMessageId: msg.id,
    text: msg.text,
    ...(msg.images && msg.images.length > 0 ? { images: msg.images } : {}),
    ...(shouldSteer ? { streamingBehavior: "steer" as const } : {}),
  });
  // Record the clientMessageId for the ingress idempotency guard
  // (story-extension-user-message-ingress-idempotency) so a later duplicate
  // frame is suppressed before _wakeAgent.
  _sdkSessionProjection.recordDeliveredUserMessageId(sessionId, msg.id);
  if (_isAuthoritativeTranscriptRecord(recorded)) {
    const ts = _sdkSessionProjection.recordedTranscriptTs(eventId) ?? producedAt;
    const echo: ServerMessage = _withCurrentSession({
      type: "user_message",
      id: msg.id,
      text: msg.text,
      ...(msg.images && msg.images.length > 0 ? { images: msg.images } : {}),
      ...(shouldSteer ? { streaming_behavior: "steer" as const } : {}),
      ts,
    });
    _owners.broadcast(echo);
  }
}

function _enqueuePendingDelivery(prepared: PreparedUserDelivery, enqueuedAt = Date.now()): void {
  if (_pendingDeliveryQueue.length >= kPendingDeliveryQueueMax) {
    const dropped = _pendingDeliveryQueue.shift();
    if (dropped) {
      clearTimeout(dropped.timeout);
      console.warn(`[outpost-pi] dropping queued delivery id=${dropped.msg.id}: replay queue full`);
      _deliveryDebugLog.log({ tag: "queue_dropped", id: dropped.msg.id, reason: "replay queue full", roomId: _myRoomId ?? undefined });
      _sendDeliveryError(dropped.sender, dropped.msg.id, "agent session did not re-arm before the replay queue filled");
    }
  }
  const queueId = _nextPendingDeliveryQueueId++;
  const entry: PendingDeliveryEntry = {
    ...prepared,
    queueId,
    enqueuedAt,
    timeout: _schedulePendingDeliveryTimeout(queueId, prepared, enqueuedAt),
  };
  _pendingDeliveryQueue.push(entry);
  _deliveryDebugLog.log({
    tag: "delivery_pending",
    id: prepared.msg.id,
    queueLen: _pendingDeliveryQueue.length,
    ttlMs: _pendingDeliveryTtlMs,
    roomId: _myRoomId ?? undefined,
  });
}

function _schedulePendingDeliveryTimeout(
  queueId: number,
  prepared: PreparedUserDelivery,
  enqueuedAt: number,
): ReturnType<typeof setTimeout> {
  const elapsed = Date.now() - enqueuedAt;
  const remaining = Math.max(0, _pendingDeliveryTtlMs - elapsed);
  return setTimeout(() => {
    const index = _pendingDeliveryQueue.findIndex((entry) => entry.queueId === queueId);
    if (index < 0) return;
    const entry = _pendingDeliveryQueue[index]!;
    // A replacement is in progress — a successor will re-arm and drain the
    // queue. Do not expire to internal_error; renew the TTL window so the
    // message survives the (possibly >5s) replacement gap. The terminal
    // `quit` path fails the queue via clearStaleContexts; bounded capacity
    // limits growth. See feature-session-stable-message-delivery gap-window gate.
    if (getOutpostPiRuntimeCoordinator().isReplacing()) {
      // Absolute deadline: if the replacement has been stuck longer than the
      // cap (successor creation failed and the SDK propagated the error while
      // RPC mode stayed alive, leaving the coordinator permanently REPLACING),
      // stop renewing and surface a real internal_error. Bounds the renew
      // loop. Matches the app-side deliveryPendingEchoTimeout (60s).
      if (Date.now() - entry.enqueuedAt >= _pendingDeliveryAbsoluteDeadlineMs) {
        _pendingDeliveryQueue.splice(index, 1);
        _deliveryDebugLog.log({ tag: "queue_dropped", id: prepared.msg.id, reason: "absolute deadline exceeded during stuck replacement", roomId: _myRoomId ?? undefined });
        _sendDeliveryError(prepared.sender, prepared.msg.id, "agent session did not re-arm before queued delivery expired");
        return;
      }
      _deliveryDebugLog.log({ tag: "queue_renewed", id: prepared.msg.id, reason: "replacement in progress", roomId: _myRoomId ?? undefined });
      entry.timeout = _schedulePendingDeliveryTimeout(queueId, prepared, Date.now());
      return;
    }
    _pendingDeliveryQueue.splice(index, 1);
    _deliveryDebugLog.log({ tag: "queue_dropped", id: prepared.msg.id, reason: "ttl expired", roomId: _myRoomId ?? undefined });
    _sendDeliveryError(prepared.sender, prepared.msg.id, "agent session did not re-arm before queued delivery expired");
  }, remaining);
}

function _failPendingDeliveryQueue(detail: string): void {
  const entries = _pendingDeliveryQueue.splice(0);
  for (const entry of entries) {
    clearTimeout(entry.timeout);
    console.warn(`[outpost-pi] failing queued delivery id=${entry.msg.id}: ${detail}`);
    _deliveryDebugLog.log({ tag: "queue_dropped", id: entry.msg.id, reason: detail, roomId: _myRoomId ?? undefined });
    _sendDeliveryError(entry.sender, entry.msg.id, detail);
  }
}

function _drainPendingDeliveryQueue(): void {
  if (_pendingDeliveryQueue.length === 0) return;
  const entries = _pendingDeliveryQueue.splice(0);
  for (const entry of entries) {
    clearTimeout(entry.timeout);
    void (async () => {
      const wake = await _attemptUserDelivery(entry);
      _deliveryDebugLog.log({ tag: "queue_drained", id: entry.msg.id, wakeOk: wake.ok, roomId: _myRoomId ?? undefined });
      if (wake.ok) return;
      const detail = wake.detail ?? "agent session not bound yet";
      if (!wake.recoverable) {
        _sendDeliveryError(entry.sender, entry.msg.id, detail);
        return;
      }
      if (Date.now() - entry.enqueuedAt >= _pendingDeliveryTtlMs) {
        _sendDeliveryError(entry.sender, entry.msg.id, detail);
        return;
      }
      _enqueuePendingDelivery(entry, entry.enqueuedAt);
    })().catch((err: unknown) => {
      const detail = err instanceof Error ? err.message : String(err);
      _sendDeliveryError(entry.sender, entry.msg.id, detail);
    });
  }
}

async function _deliverUserMessage(
  msg: UserClientMessage,
  sender: PlainPeerChannel | null,
  mode: "auto" | "normal" = "auto",
): Promise<void> {
  const fenceReason = _freshSessionShutdown.fenceReason;
  if (fenceReason !== null) {
    _sendDeliveryRetry(sender, msg.id, fenceReason);
    return;
  }
  const prepared = _prepareUserDelivery(msg, sender, mode);
  _deliveryDebugLog.log({
    tag: "msg_received",
    id: msg.id,
    source: mode === "normal" ? "queued" : "app",
    steer: prepared.shouldSteer,
    roomId: _myRoomId ?? undefined,
  });
  const wake = await _attemptUserDelivery(prepared);
  if (wake.ok) return;
  if (wake.recoverable) {
    _enqueuePendingDelivery(prepared);
    _sendDeliveryPending(sender, msg.id);
    return;
  }
  _sendDeliveryError(sender, msg.id, wake.detail ?? "agent session not bound yet");
}

function _maybeDrainQueuedMessage(): void {
  _sdkSessionProjection.maybeDrainQueuedMessage(
    (queued) => _deliverUserMessage(queued, null, "normal"),
    (queued, error) => {
      console.error(`[outpost-pi] queued delivery id=${queued.id} rejected: ${String(error)}`);
    },
  );
}

function _maybeSendLateAttachSessionSync(): void {
  _sdkSessionProjection.maybeSendLateAttachSessionSync((turnId) => _buildSessionHistoryMessage(turnId, undefined));
}

/** Resolve hot-reload state paths lazily so tests can redirect
 * `OUTPOST_PI_HOME` after module evaluation. */
function _outpostPiRemoteDir(): string {
  return process.env["OUTPOST_PI_HOME"] || join(homedir(), ".pi", "remote");
}

function _stateOwnerUid(): number | undefined {
  return typeof process.getuid === "function" ? process.getuid() : undefined;
}

function _isOwnerOnlyDirectory(path: string): boolean {
  try {
    const stat = lstatSync(path);
    if (!stat.isDirectory() || (stat.mode & 0o777) !== 0o700) return false;
    const uid = _stateOwnerUid();
    return uid === undefined || stat.uid === uid;
  } catch {
    return false;
  }
}

function _isOwnerOnlyRegularFile(path: string): boolean {
  try {
    const stat = lstatSync(path);
    if (!stat.isFile() || (stat.mode & 0o777) !== 0o600) return false;
    const uid = _stateOwnerUid();
    return uid === undefined || stat.uid === uid;
  } catch {
    return false;
  }
}

function _secureHotReloadRemoteDir(): string | null {
  const dir = _outpostPiRemoteDir();
  if (_isOwnerOnlyDirectory(dir)) return dir;
  if (existsSync(dir)) {
    console.warn(`[outpost-pi] refusing hot-reload state in insecure directory: ${dir}`);
  }
  return null;
}

function _ensureHotReloadRemoteDir(): string {
  const dir = _outpostPiRemoteDir();
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  if (!_isOwnerOnlyDirectory(dir)) {
    throw new Error(`[outpost-pi] hot-reload state directory must be owner-only (0700): ${dir}`);
  }
  return dir;
}

function _removeIfOwnerOnlyRegularFile(path: string): void {
  if (!_isOwnerOnlyRegularFile(path)) return;
  try { unlinkSync(path); } catch { /* best-effort stale-state cleanup */ }
}

function _sweepStaleRuntimeIdentities(dir: string): void {
  let names: string[];
  try { names = readdirSync(dir); } catch { return; }
  for (const name of names) {
    // Sweep PID-scoped state files left by crashed/restarted processes.
    const pidPrefixes = [".runtime-self-", ".claimed-", ".restart-marker-"];
    const prefix = pidPrefixes.find((p) => name.startsWith(p));
    if (!prefix) continue;
    const pidText = name.slice(prefix.length);
    if (!/^[0-9]+$/.test(pidText)) continue;
    const path = join(dir, name);
    if (!_isOwnerOnlyRegularFile(path)) continue;
    const pid = Number(pidText);
    if (!Number.isSafeInteger(pid) || pid <= 0 || pid === process.pid) continue;
    try {
      process.kill(pid, 0);
    } catch (error) {
      // EPERM means the process exists but is not probeable; only remove an
      // identity when the kernel positively reports that its PID is gone.
      if (error && typeof error === "object" && "code" in error && (error as { code?: unknown }).code === "EPERM") continue;
      _removeIfOwnerOnlyRegularFile(path);
    }
  }
}

function _hotReloadArmedPath(): string {
  return join(_outpostPiRemoteDir(), `.hot-reload-armed-${process.pid}`);
}

function _hotReloadClaimedPath(): string {
  return join(_outpostPiRemoteDir(), `.claimed-${process.pid}`);
}

function _restartMarkerPath(): string {
  // The foreground wrapper records the exact exec'd Pi child PID, then accepts
  // only this owner-only regular marker after that child exits successfully.
  return join(_outpostPiRemoteDir(), `.restart-marker-${process.pid}`);
}

const _hotReloadNonce = randomUUID();

/** Test-only override for resetting the shared synchronous ingress fence. */
export function _setHotReloadingForTest(value: boolean): void {
  if (value) _freshSessionShutdown.beginHotReloadFence();
  else _freshSessionShutdown.resetForTest();
}

/** Test-host seam for observing the production owner-delivery fence. */
export function _getOwnerDeliveryFenceReasonForTest():
  | "hot_reload"
  | "fresh_session"
  | null {
  return _freshSessionShutdown.fenceReason;
}

/** Await protected owner ingress and outbound sequence persistence in tests. */
export async function _drainOwnerChannelsForTest(): Promise<void> {
  const drains = _owners.entries().map(({ channel }) => {
    const drainable = channel as PeerChannel & { whenIdle?: () => Promise<void> };
    return drainable.whenIdle?.() ?? Promise.resolve();
  });
  await Promise.allSettled(drains);
}

/** Publish this process's nonce so an external arming command can target it. */
function _writeRuntimeIdentity(): void {
  if (process.env["OUTPOST_PI_DAEMON"] === "1") return;
  try {
    const dir = _ensureHotReloadRemoteDir();
    _sweepStaleRuntimeIdentities(dir);
    // A failed prior hook may have left this process's claim behind while a
    // session replacement was already underway. It must not fence the successor.
    _removeIfOwnerOnlyRegularFile(_hotReloadClaimedPath());
    const identityPath = join(dir, `.runtime-self-${process.pid}`);
    if (existsSync(identityPath)) {
      if (!_isOwnerOnlyRegularFile(identityPath)) {
        console.warn(`[outpost-pi] refusing insecure hot-reload identity: ${identityPath}`);
        return;
      }
      _removeIfOwnerOnlyRegularFile(identityPath);
    }
    writeFileSync(
      identityPath,
      JSON.stringify({ pid: process.pid, nonce: _hotReloadNonce, ts: Date.now() }),
      { mode: 0o600, flag: "wx" },
    );
    _removeIfOwnerOnlyRegularFile(_restartMarkerPath());
  } catch (error) {
    console.warn(`[outpost-pi] hot-reload runtime identity unavailable: ${String(error)}`);
  }
}

/** Arm one process-scoped hot-reload request from the interactive command surface. */
function _armHotReload(ctx?: OutpostPiUiContext): void {
  if (process.env["OUTPOST_PI_DAEMON"] === "1") return;
  const dir = _secureHotReloadRemoteDir();
  if (!dir) {
    _notify("[outpost-pi] hot-reload state directory is missing or insecure", "warning", ctx);
    return;
  }
  const togglePath = join(dir, ".hot-reload-enabled");
  if (!_isOwnerOnlyRegularFile(togglePath)) {
    _notify("[outpost-pi] hot-reload toggle is off — run /outpost-pi hot-reload on first", "warning", ctx);
    return;
  }
  try {
    writeFileSync(
      join(dir, `.hot-reload-armed-${process.pid}`),
      JSON.stringify({ nonce: _hotReloadNonce, ts: Date.now() }),
      { mode: 0o600, flag: "wx" },
    );
    _notify(`[outpost-pi] hot-reload armed — restart fires at next agent_settled (pid=${process.pid})`, "info", ctx);
  } catch {
    _notify(`[outpost-pi] hot-reload is already armed for pid=${process.pid}`, "warning", ctx);
  }
}

function _cmdHotReload(args: string, ctx: Pick<ExtensionContext, "ui">): void {
  const command = args.trim() || "status";
  if (process.env["OUTPOST_PI_DAEMON"] === "1") {
    _notify("[outpost-pi] hot-reload is disabled in daemon mode", "warning", ctx);
    return;
  }
  let dir: string;
  try { dir = _ensureHotReloadRemoteDir(); }
  catch (error) {
    _notify(`[outpost-pi] hot-reload state directory unavailable: ${String(error)}`, "warning", ctx);
    return;
  }
  if (command === "on") {
    try { writeFileSync(join(dir, ".hot-reload-enabled"), "", { mode: 0o600, flag: "wx" }); } catch { /* already enabled */ }
    _notify("[outpost-pi] hot-reload enabled", "info", ctx);
    return;
  }
  if (command === "off") {
    // Remove the toggle + ALL PID-scoped state files (armed, claimed, identity,
    // marker) across all processes — not just THIS process. A per-process glob
    // prevents a stale armed request from another pi from firing after re-enable.
    _removeIfOwnerOnlyRegularFile(join(dir, ".hot-reload-enabled"));
    try {
      for (const name of readdirSync(dir)) {
        if (name.startsWith(".hot-reload-armed-") ||
            name.startsWith(".claimed-") ||
            name.startsWith(".runtime-self-") ||
            name.startsWith(".restart-marker-")) {
          _removeIfOwnerOnlyRegularFile(join(dir, name));
        }
      }
    } catch { /* best-effort */ }
    _notify("[outpost-pi] hot-reload disabled (all pending requests cleared)", "info", ctx);
    return;
  }
  if (command === "arm") {
    _armHotReload(ctx);
    return;
  }
  if (command === "status") {
    _notify(
      `[outpost-pi] hot-reload: ${_isOwnerOnlyRegularFile(join(dir, ".hot-reload-enabled")) ? "on" : "off"}, ` +
      `${_isOwnerOnlyRegularFile(_hotReloadArmedPath()) ? "armed" : "not armed"} (pid=${process.pid})`,
      "info",
      ctx,
    );
    return;
  }
  _notify("[outpost-pi] Usage: /outpost-pi hot-reload <on|off|arm|status>", "warning", ctx);
}

/**
 * Restart only after Pi reports that all agent work has settled.
 *
 * This handler is intentionally synchronous. The armed request is bound to the
 * current PID and module nonce, and O_EXCL on the claim file makes the restart
 * single-winner when multiple settled notifications arrive. `agent_settled` is
 * not an end-to-end WebSocket flush acknowledgment: Pi's graceful shutdown
 * provides a bounded local drain, while the app rehydrates from session_sync
 * after reconnect if the final frame was not received.
 */
function _maybeRestartForExtensionReload(ctx: Pick<ExtensionContext, "isIdle">): void {
  if (process.env["OUTPOST_PI_DAEMON"] === "1" || _disposed) return;
  if (_freshSessionShutdown.fenceReason !== null) return;

  const dir = _secureHotReloadRemoteDir();
  if (!dir) return;
  const togglePath = join(dir, ".hot-reload-enabled");
  if (!_isOwnerOnlyRegularFile(togglePath)) return;

  const armedPath = join(dir, `.hot-reload-armed-${process.pid}`);
  // lstat-based admission rejects symlinks and directories without touching
  // their targets. This is the security boundary for OUTPOST_PI_HOME state.
  if (!_isOwnerOnlyRegularFile(armedPath)) return;

  let request: { nonce?: unknown; ts?: unknown };
  try {
    const parsed: unknown = JSON.parse(readFileSync(armedPath, "utf8"));
    if (!parsed || typeof parsed !== "object") return;
    request = parsed as { nonce?: unknown; ts?: unknown };
  } catch {
    return;
  }
  if (request.nonce !== _hotReloadNonce) {
    _removeIfOwnerOnlyRegularFile(armedPath);
    return;
  }
  if (typeof request.ts === "number" && Date.now() - request.ts > 5 * 60_000) {
    _removeIfOwnerOnlyRegularFile(armedPath);
    return;
  }

  if (_disposed || !ctx.isIdle()) return;

  const claimedPath = join(dir, `.claimed-${process.pid}`);
  try {
    writeFileSync(claimedPath, "", { mode: 0o600, flag: "wx" });
  } catch {
    return;
  }
  if (_disposed) {
    _removeIfOwnerOnlyRegularFile(claimedPath);
    return;
  }

  const markerPath = _restartMarkerPath();
  if (existsSync(markerPath)) {
    if (!_isOwnerOnlyRegularFile(markerPath)) {
      _removeIfOwnerOnlyRegularFile(claimedPath);
      return;
    }
    _removeIfOwnerOnlyRegularFile(markerPath);
  }
  try {
    writeFileSync(markerPath, String(process.pid), { mode: 0o600, flag: "wx" });
  } catch {
    // A missing marker deliberately makes the wrapper stop instead of
    // relaunching a process whose restart intent was not durably recorded.
    _removeIfOwnerOnlyRegularFile(claimedPath);
    return;
  }
  _removeIfOwnerOnlyRegularFile(armedPath);
  if (_disposed) {
    _removeIfOwnerOnlyRegularFile(claimedPath);
    return;
  }
  if (!_freshSessionShutdown.beginHotReloadFence()) {
    _removeIfOwnerOnlyRegularFile(claimedPath);
    _removeIfOwnerOnlyRegularFile(markerPath);
    return;
  }
  process.kill(process.pid, "SIGTERM");
}

export function _routeClientMessageFrom(
  sender: PlainPeerChannel,
  msg: ClientMessage,
  ctx: Pick<ExtensionContext, "abort">,
): void {
  const sessionGate = validateClientSession(msg, _currentRemoteSessionId(_lastEventCtx ?? _lastCtx));
  if (!sessionGate.ok) {
    sender.send({
      type: "error",
      code: sessionGate.code,
      in_reply_to: "id" in msg ? msg.id : undefined,
      message: sessionGate.message,
      session_id: sessionGate.currentSessionId,
    });
    return;
  }

  // session_sync has its own internal guards — handle before the strict
  // pi-binding guard so a missing _pi doesn't drop the reply.
  if (msg.type === "session_sync") {
    _handleSessionSync(sender, msg);
    return;
  }
  if (msg.type === "cancel") {
    try {
      const aborted = _abortCurrentTurn(ctx);
      if (!aborted) {
        _sendRenderableTranscriptError(
          sender,
          "internal_error",
          "No active Pi context to abort",
          msg.id,
        );
        return;
      }
      _applyTurnAndPublish({ type: "cancelled", turnId: msg.target_id });
      sender.send(_withCurrentSession({ type: "cancelled", in_reply_to: msg.id, target_id: msg.target_id }));
    } catch (err) {
      _sendRenderableTranscriptError(
        sender,
        "internal_error",
        `Abort failed: ${String(err)}`,
        msg.id,
      );
    }
    return;
  }
  if (msg.type === "user_message") {
    const fenceReason = _freshSessionShutdown.fenceReason;
    if (fenceReason !== null) {
      _sendDeliveryRetry(sender, msg.id, fenceReason);
      return;
    }
  }
  if (_disposed) {
    _sessionUnavailable(sender, msg.id);
    return;
  }
  switch (msg.type) {
    case "user_message":
      // Source-of-truth rebroadcast (plan/24 W2D fix). Echo the message
      // back to every attached owner (sender included) after the SDK accepts
      // the handoff, so optimistic app bubbles only confirm on real delivery.
      // The user_message is also recorded in the transcript event log after
      // SDK acceptance, so a later `session_sync` replays it in history.
      void _deliverUserMessage(msg, sender).catch((err: unknown) => {
        const detail = err instanceof Error ? err.message : String(err);
        _sendDeliveryError(sender, msg.id, detail);
      });
      break;
    case "queued_message_set":
      _applyTurnAndPublish({ type: "queued_message_set", id: msg.id, text: msg.text });
      _broadcastQueuedMessageState();
      break;
    case "queued_message_clear":
      _applyTurnAndPublish({ type: "queued_message_clear" });
      _broadcastQueuedMessageState();
      break;
    case "approve_tool":
      // Approval gate was removed (revised Plan 10.2). Type kept in
      // ClientMessage for forward-compat with a future permissions model;
      // ignore silently if the app still sends it from an older build.
      break;
    case "ping":
      sender.send({ type: "pong", in_reply_to: msg.id });
      break;
    case "pair_request":
      // Already paired — ignore subsequent pair_request to maintain idempotency.
      // (Token is already consumed and peer is in peers.json.)
      break;
    // Plan/28 — Typed app actions. Each delegates to the pure handler in
    // `actions/handlers.ts`; this adapter now obtains Pi SDK capabilities only
    // through SdkSessionProjection's fresh bindings. A session replacement clears
    // stale bindings, so app actions either hit the current SDK context or return
    // an explicit sender-scoped error.
    case "session_compact":
      handleSessionCompact(_sdkSessionProjection.freshActionCtx(), sender, msg);
      break;
    case "session_new": {
      const actionCtx = _sdkSessionProjection.freshCommandActionCtx();
      const newSession = actionCtx?.newSession;
      if (!newSession) {
        if (!_isFreshSessionRestartManaged()) {
          sender.send({
            type: "action_error",
            session_id: msg.session_id,
            in_reply_to: msg.id,
            action: "session_new",
            error: "fresh_session_restart_unavailable: /new is not available in this agent mode",
          });
          break;
        }
        const runtime = _activeOutpostPiRuntime;
        if (!runtime?.isOwner()) {
          sender.send({
            type: "action_error",
            session_id: msg.session_id,
            in_reply_to: msg.id,
            action: "session_new",
            error: "fresh_session_runtime_stale: active lifecycle runtime is unavailable",
          });
          break;
        }

        // Managed processes cannot use the command-only SDK newSession API.
        // Fence new prompts synchronously, finish admitted SDK deliveries, then
        // stage the ACK/reset tail before normal runtime disposal and exit 42.
        void _freshSessionShutdown.request({
          stageAcknowledgementAndReset: () => {
            sender.send({
              type: "action_ok",
              session_id: msg.session_id,
              in_reply_to: msg.id,
              action: "session_new",
            });
            _resetSessionForNew(msg.id);
          },
          shutdownRuntime: (reason) => runtime.dispose(reason),
        }).then((result) => {
          if (result.status !== "already_quiescing"
              && result.status !== "stale_runtime") return;
          try {
            sender.send({
              type: "action_error",
              session_id: msg.session_id,
              in_reply_to: msg.id,
              action: "session_new",
              error: result.status === "already_quiescing"
                ? "fresh_session_already_quiescing: another request owns shutdown"
                : "fresh_session_runtime_stale: lifecycle ownership changed",
            });
          } catch { /* owner channel may already be detached by the winning request */ }
        }).catch(() => {
          // Deadline/process-manager recovery owns terminal failure. Do not emit
          // a second action result after the staged ACK/reset tail.
        });
        break;
      }
      void handleSessionNew(
        { ...actionCtx, newSession },
        sender,
        msg,
        (freshCtx) => {
          // newSession marks every pre-replacement SDK context stale. Re-capture
          // the fresh command/event/message/action capabilities in one projection
          // method and drop the old module-level _pi so later app actions cannot
          // fall back to a known-stale SDK object.
          _bindReplacementSessionContext(freshCtx);
          if (_disposed && _messageApi) {
            _disposed = false;
            _startRootInBackground(
              freshCtx as unknown as Pick<ExtensionContext, "ui" | "cwd">,
              "session-replacement",
            );
          }
        },
      ).then((created) => {
        // Pi-side reset is durable only here: handleSessionNew swaps the SDK
        // session, but the Outpost-Pi session clock and transcript event log live
        // in SdkSessionProjection. Rotate them and fan out an empty history as a
        // compatibility notification for every owner, not just the sender.
        if (created) _resetSessionForNew(msg.id);
      });
      break;
    }
    case "model_set": {
      const pi = _sdkSessionProjection.currentActionPi("model_set");
      if (!pi) {
        _sessionUnavailable(sender, msg.id, "Pi model API unavailable for the current session");
        break;
      }
      void handleModelSet(
        pi,
        _sdkSessionProjection.freshActionCtx(),
        ensureModelRegistry(),
        sender,
        msg,
        _persistModelDefault,
      );
      break;
    }
    case "thinking_set": {
      const pi = _sdkSessionProjection.currentActionPi("thinking_set");
      if (!pi) {
        _sessionUnavailable(sender, msg.id, "Pi thinking API unavailable for the current session");
        break;
      }
      handleThinkingSet(pi, sender, msg);
      break;
    }
    case "list_models":
      handleListModels(
        _sdkSessionProjection.freshActionCtx(),
        ensureModelRegistry(),
        {
          send: (reply) => {
            if (reply.type === "error" && reply.code === "internal_error") {
              _sendRenderableTranscriptError(
                sender,
                "internal_error",
                reply.message,
                reply.in_reply_to,
              );
              return;
            }
            sender.send(reply);
          },
        },
        msg,
      );
      break;
    case "capture_upload_begin":
    case "capture_upload_chunk":
    case "capture_upload_end": {
      const ownerId = _owners.entries().find((entry) => entry.channel === sender)?.peerId;
      if (!ownerId) {
        sender.send(_withCurrentSession({
          type: "capture_upload_error",
          in_reply_to: msg.id,
          upload_id: msg.upload_id,
          code: "not_found",
          message: "Capture upload owner channel is not active.",
        }));
        break;
      }
      const captureUploads = _captureUploads;
      if (!captureUploads) {
        sender.send(_withCurrentSession({
          type: "capture_upload_error",
          in_reply_to: msg.id,
          upload_id: msg.upload_id,
          code: "not_found",
          message: "Capture upload runtime is not active.",
        }));
        break;
      }
      void captureUploads.handle(ownerId, sender, msg).catch(() => {
        sender.send(_withCurrentSession({
          type: "capture_upload_error",
          in_reply_to: msg.id,
          upload_id: msg.upload_id,
          code: "io_error",
          message: "Capture delivery failed unexpectedly.",
        }));
      });
      break;
    }
  }
}

/**
 * Backward-compatible shim for legacy callers + tests that didn't track
 * a specific sender channel. Routes to the most recently attached owner,
 * mirroring the pre-W2D singleton behavior.
 */
const routeClientMessageForTest = (
  msg: ClientMessage,
  ctx: Pick<ExtensionContext, "abort">,
): void => ownerHarness.fallbackRoute(msg, ctx);

export const outpostPiTestHarness: OutpostPiTestHarness = createOutpostPiTestHarness({
  connect: (ctx) => connectForTest(ctx),
  stop: (ctx) => stopForTest(ctx),
  state: () => getStateForTest(),
  roomId: () => getRoomIdForTest(),
  name: () => {
    const cwd = _lastCtx?.cwd ?? _myRoomMeta?.cwd;
    return cwd ? _displayName(cwd) : null;
  },
  meshAddress: () => _meshNode?.address() ?? null,
  meshBridgeActive: () => _meshNode?.hasBridge() ?? false,
  meshPeers: async () => {
    if (!_meshNode) return [];
    const reply = await _meshNode.request("broker", { type: "list_peers" }, 2000);
    const body = reply.body as {
      peers_detailed?: Array<{ pc?: string; address?: string }>;
    } | null;
    return (body?.peers_detailed ?? [])
      .filter((peer) => typeof peer.pc === "string" && typeof peer.address === "string")
      .map((peer) => peer.address!);
  },
  meshTarget: (pcPubkey, remoteAddress) =>
    _pairingCoordinator.meshTargetForTest(pcPubkey, remoteAddress),
  sendDirectMeshMessage: (input) => _meshNode?.sendEnvelopeForTest(input) ?? false,
  refreshMeshMembership: () => _pairingCoordinator.refreshMembershipForTest(),
  routeClientMessage: (message, ctx) => routeClientMessageForTest(message, ctx),
});

// ── session_sync handler + helpers ────────────────────────────────────────────

/**
 * `session_sync` is a per-sender query: the owner asking gets the reply,
 * not the whole broadcast. Otherwise a session_sync from owner A would
 * also dump history to owner B's wire — duplicate traffic + the wrong
 * `in_reply_to`.
 */
function _handleSessionSync(
  sender: PlainPeerChannel,
  msg: Extract<ClientMessage, { type: "session_sync" }>,
): void {
  sender.send(_currentQueueStateMessage());

  const history = _buildSessionHistoryMessage(msg.id, msg.limit);
  sender.send(_owners.arbitrateSessionHistory(sender, history));
}

function _buildSessionHistoryMessage(
  inReplyTo: string,
  limit: number | undefined,
): Extract<ServerMessage, { type: "session_history" }> {
  return _sdkSessionProjection.buildSessionHistoryMessage(inReplyTo, limit);
}

/**
 * Resets the Pi-side session view after a SUCCESSFUL `session_new`. The
 * transcript event log answers `session_sync` by replaying session-scoped facts;
 * rotating the remote session id and clearing that log is the correctness
 * boundary, independent of whether any app chooses to replace or preserve local
 * rows for older sessions. The empty `session_history` broadcast is only a
 * compatibility notification for already-attached owners.
 *
 * Unlike a per-request session_history reply (which must go to the sender
 * channel only), this is an intentional fan-out: a new session is global state,
 * so every owner may reconcile immediately.
 */
function _resetSessionForNew(inReplyTo: string): void {
  _applyTurnAndPublish({ type: "session_shutdown" });
  _resetTurnSnapshot();
  _publishWorking(false);
  _broadcastQueuedMessageState();
  _sdkSessionProjection.resetSessionForNew(inReplyTo);
  // Clear in-flight delivery attempts so a stale entry from the prior
  // session doesn't coalesce a fresh send in the new session. (The dedupe
  // key is sessionId-scoped, so this is belt-and-suspenders, but clearing
  // avoids lingering promises from a replaced session.)
  _inflightUserDeliveries.clear();
  _captureUploads?.detachAll();
}

type ToolArgs = Record<string, unknown>;
type DiffLine =
  | { kind: "context"; oldLine?: number; newLine?: number; text: string }
  | { kind: "remove"; oldLine?: number; text: string }
  | { kind: "add"; newLine?: number; text: string }
  | { kind: "ellipsis" };

function _enrichToolArgs(tool: string, args: unknown): ToolArgs {
  if (!args || typeof args !== "object") return {};
  const base = args as ToolArgs;

  switch (tool.toLowerCase()) {
    case "edit":
      return _enrichEditToolArgs(base);
    default:
      return base;
  }
}

function _enrichEditToolArgs(base: ToolArgs): ToolArgs {
  const filePath = _stringArg(base, ["path", "file_path"]);
  const rawEdits = base["edits"];
  const edits = Array.isArray(rawEdits) ? rawEdits : [base];
  const text = _readToolFile(filePath);
  const hunks: { lines: DiffLine[] }[] = [];
  let searchFrom = 0;
  for (const rawEdit of edits) {
    if (!rawEdit || typeof rawEdit !== "object") continue;
    const edit = rawEdit as ToolArgs;
    const oldText = _stringArg(edit, ["oldText", "old_text", "old_string", "oldString"]);
    const newText = _stringArg(edit, ["newText", "new_text", "new_string", "newString"]);
    if (!oldText && !newText) continue;

    const matchAt = oldText && text !== null ? text.indexOf(oldText, searchFrom) : -1;
    const fallbackAt = oldText && matchAt < 0 && text !== null ? text.indexOf(oldText) : matchAt;
    const startOffset = fallbackAt >= 0 ? fallbackAt : searchFrom;
    if (text === null) continue;
    const hunk = _buildEditHunk(text, startOffset, oldText, newText);
    if (hunk.length > 0) hunks.push({ lines: hunk });
    searchFrom = startOffset + Math.max(oldText.length, 1);
  }

  return hunks.length === 0 ? base : { ...base, hunks };
}

function _readToolFile(filePath: string): string | null {
  if (!filePath) return null;
  const cwd = _currentCwd();
  const homePath = filePath.startsWith("~/") && process.env.HOME
    ? resolve(process.env.HOME, filePath.slice(2))
    : null;
  const candidates = [filePath, resolve(cwd, filePath), resolve(process.cwd(), filePath), homePath]
    .filter((p): p is string => typeof p === "string");
  for (const candidate of candidates) {
    try {
      return readFileSync(candidate, "utf8");
    } catch {
      // try next candidate
    }
  }
  return null;
}


function _buildEditHunk(
  fileText: string,
  startOffset: number,
  oldText: string,
  newText: string,
): DiffLine[] {
  const context = 4;
  const fileLines = fileText.split("\n");
  const oldLines = _splitPreviewLines(oldText);
  const newLines = _splitPreviewLines(newText);
  const oldStart = _lineNumberAt(fileText, startOffset);
  const newStart = oldStart;
  const startIndex = oldStart - 1;
  const beforeStart = Math.max(0, startIndex - context);
  const afterStart = startIndex + oldLines.length;
  const afterEnd = Math.min(fileLines.length, afterStart + context);
  const out: DiffLine[] = [];

  if (beforeStart > 0) out.push({ kind: "ellipsis" });
  for (let i = beforeStart; i < startIndex; i++) {
    out.push({ kind: "context", oldLine: i + 1, newLine: i + 1, text: fileLines[i] ?? "" });
  }
  let commonPrefix = 0;
  while (
    commonPrefix < oldLines.length &&
    commonPrefix < newLines.length &&
    oldLines[commonPrefix] === newLines[commonPrefix]
  ) {
    commonPrefix++;
  }

  let commonSuffix = 0;
  while (
    commonSuffix < oldLines.length - commonPrefix &&
    commonSuffix < newLines.length - commonPrefix &&
    oldLines[oldLines.length - 1 - commonSuffix] === newLines[newLines.length - 1 - commonSuffix]
  ) {
    commonSuffix++;
  }

  for (let i = 0; i < commonPrefix; i++) {
    out.push({ kind: "context", oldLine: oldStart + i, newLine: newStart + i, text: oldLines[i] ?? "" });
  }
  for (let i = commonPrefix; i < oldLines.length - commonSuffix; i++) {
    out.push({ kind: "remove", oldLine: oldStart + i, text: oldLines[i] ?? "" });
  }
  for (let i = commonPrefix; i < newLines.length - commonSuffix; i++) {
    out.push({ kind: "add", newLine: newStart + i, text: newLines[i] ?? "" });
  }
  for (let i = oldLines.length - commonSuffix; i < oldLines.length; i++) {
    const newLine = newStart + newLines.length - (oldLines.length - i);
    out.push({ kind: "context", oldLine: oldStart + i, newLine, text: oldLines[i] ?? "" });
  }
  for (let i = afterStart; i < afterEnd; i++) {
    const newLine = newStart + newLines.length + (i - afterStart);
    out.push({ kind: "context", oldLine: i + 1, newLine, text: fileLines[i] ?? "" });
  }
  if (afterEnd < fileLines.length) out.push({ kind: "ellipsis" });
  return out;
}

function _lineNumberAt(text: string, offset: number): number {
  let line = 1;
  for (let i = 0; i < Math.max(0, offset); i++) if (text[i] === "\n") line++;
  return line;
}

function _splitPreviewLines(text: string): string[] {
  if (!text) return [];
  const lines = text.split("\n");
  if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
  return lines;
}

function _stringArg(args: ToolArgs, keys: string[]): string {
  for (const key of keys) {
    const value = args[key];
    if (typeof value === "string") return value;
  }
  return "";
}

// ── Standalone CLI ────────────────────────────────────────────────────────────

if (isDirectRun(import.meta.url, process.argv[1])) {
  await runStandaloneOutpostPiCli(process.argv, createStandaloneCliDeps({
    listPeers: () => listPeers(),
    removePeer: (remoteEpk) => removePeer(remoteEpk),
    saveRelayConfig: (url) => { saveConfig({ relay: url }); },
    daemon: _daemonCommands,
    cron: _cronCommands,
    service: _serviceCommands,
    probeListPeers: () => probeListPeers(sessionSockPath(LOCAL_SESSION_NAME)),
    formatPeerInventory: (peers) => formatPeerInventory([...peers]),
    launchClaude: (args) => launchClaudeCli(args, import.meta.url),
    restartSupervisor: () => restartSupervisor(),
  }));
}

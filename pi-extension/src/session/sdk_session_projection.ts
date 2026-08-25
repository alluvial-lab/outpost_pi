import type {
  ExtensionAPI,
  ExtensionCommandContext,
  ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import type { ClientMessage, ServerMessage, ThinkingLevel } from "../protocol/types.js";
import { SERVER_MESSAGE_DISCRIMINATORS } from "../protocol/generated/protocol.generated.js";
import type { PeerChannel } from "../transport/peer_channel.js";
import type { MeshIngressAdmission, SdkSessionProjectionPort, WakeAgentResult } from "../extension/ports.js";
import type { ActionCtx, ActionPi, SdkModelLike } from "../actions/handlers.js";
import type { DeliveryDebugLog } from "./delivery_debug_log.js";
import { idTail } from "./delivery_debug_log.js";
import { RemoteSessionIssuer, type RemoteSessionId } from "./remote_session.js";
import {
  TRANSCRIPT_EVENT_CUSTOM_TYPE,
  encodeDurableTranscriptEventV1,
} from "./durable_transcript_event.js";
import type { TranscriptEvent } from "./transcript_event.js";
import {
  TranscriptEventLog,
  type TranscriptEventPersistence,
  type TranscriptRecordResult,
} from "./transcript_event_log.js";
import {
  initialTurnSnapshot,
  projectTurn,
  reduceTurn,
  type TurnEvent,
  type TurnProjection,
  type TurnSnapshot,
  type TurnSource,
} from "./turn_state.js";
import {
  deterministicTranscriptEventId,
  imagesFromContent,
  reconcileTranscriptContextEntries,
  projectSessionHistory,
  stringifyContent,
  transcriptUserContentSignature,
  type SdkTranscriptMessage,
  type SdkTranscriptContextEntry,
} from "./transcript_projection.js";

/** Narrow the Pi APIs that can render extension messages and wake an agent turn. */
export type AgentMessageApi = {
  sendMessage: (...args: Parameters<ExtensionAPI["sendMessage"]>) => void | Promise<void>;
  sendUserMessage: (...args: Parameters<ExtensionAPI["sendUserMessage"]>) => void | Promise<void>;
};

/** Narrow the public SDK capability that appends a custom entry to the current session. */
export type TranscriptEntryApi = Pick<ExtensionAPI, "appendEntry">;

/** Represent the optional action and message capabilities captured from a fresh SDK session context. */
export type FreshActionApi = Partial<AgentMessageApi> & Partial<ActionPi> & Partial<ActionCtx>;

type RoomMetaPatch = {
  session_id?: string;
  model?: string;
  thinking?: ThinkingLevel;
  working?: boolean;
};

/** Supply the authoritative session identity, queued state, and replay function for a history response. */
export interface SessionHistorySnapshot {
  sessionStartedAt: number;
  sessionId: RemoteSessionId;
  queued: Extract<ServerMessage, { type: "queued_message_state" }>;
  history(inReplyTo: string, limit?: number): Extract<ServerMessage, { type: "session_history" }>;
}

/** Define side effects owned by the composition root while this projection owns session-derived state. */
export interface SdkSessionProjectionOutputs {
  broadcast(message: ServerMessage): void;
  sendTo(sender: PeerChannel, message: ServerMessage): void;
  publishRoomMeta(patch: RoomMetaPatch): void;
  activeOwnerIds(): readonly string[];
  lateAttachTargets(): readonly { peerId: string; channel: PeerChannel }[];
  handleClientMessage(sender: PeerChannel, message: ClientMessage): void | Promise<void>;
  onStaleMessageApi?(api: AgentMessageApi): void;
  /** Surface a content-free diagnostic when an admitted mesh batch cannot reach the SDK. */
  onMeshDeliveryFailure?(reason: "stale_session" | "send_failed"): void;
  /** Delivery-path debug log (the extension half of cross-side observability).
   * Optional — a no-op when `OUTPOST_PI_DEBUG_LOG` is unset. The projection
   * emits `message_api_armed`/`message_api_null`/`wake_outcome`/`command_ctx`
   * from its own state transitions. See `delivery_debug_log.ts`. */
  deliveryDebugLog?: DeliveryDebugLog;
}

/** Report whether user ingress seeded a turn and provide rollback when downstream delivery fails. */
export interface SeededUserTurn {
  seeded: boolean;
  rollback(): void;
}

/** Configure the composition-owned output port used by a session projection. */
export interface SdkSessionProjectionOptions {
  outputs: SdkSessionProjectionOutputs;
  meshIngressLimits?: Partial<MeshIngressLimits>;
}

/** Bound retained mesh ingress globally and per sending peer. */
export interface MeshIngressLimits {
  maxFrames: number;
  maxBytes: number;
  maxFramesPerPeer: number;
  maxBytesPerPeer: number;
}

interface PendingMeshMessage {
  peerId: string;
  content: string;
  bytes: number;
}

interface PeerMeshAccounting {
  frames: number;
  bytes: number;
}

const DEFAULT_MESH_INGRESS_LIMITS: MeshIngressLimits = {
  maxFrames: 128,
  maxBytes: 1024 * 1024,
  maxFramesPerPeer: 32,
  maxBytesPerPeer: 256 * 1024,
};

const SYNC_LIMIT_DEFAULT = 30;

function syncLimit(): number {
  const raw = process.env["OUTPOST_PI_SYNC_LIMIT"];
  const parsed = raw ? parseInt(raw, 10) : NaN;
  return Number.isFinite(parsed) && parsed > 0 ? parsed : SYNC_LIMIT_DEFAULT;
}

function isPromiseLike(value: unknown): value is PromiseLike<void> {
  return !!value &&
    (typeof value === "object" || typeof value === "function") &&
    typeof (value as { then?: unknown }).then === "function";
}

/** Narrow an unknown SDK surface to the message APIs required for remote delivery. */
export function isAgentMessageApi(value: unknown): value is AgentMessageApi {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<AgentMessageApi>;
  return typeof candidate.sendMessage === "function" &&
    typeof candidate.sendUserMessage === "function";
}

/** Narrow an unknown SDK surface to the custom-entry capability independently of message delivery. */
export function isTranscriptEntryApi(value: unknown): value is TranscriptEntryApi {
  if (!value || typeof value !== "object") return false;
  return typeof (value as Partial<TranscriptEntryApi>).appendEntry === "function";
}

function isFreshActionApi(value: unknown): value is FreshActionApi {
  if (!value || typeof value !== "object") return false;
  const candidate = value as FreshActionApi;
  return typeof candidate.setModel === "function" ||
    typeof candidate.setThinkingLevel === "function";
}

function isStaleContextError(err: unknown): boolean {
  const message = err instanceof Error ? err.message : String(err);
  return message.includes("stale after session replacement or reload");
}

/** Project fresh SDK lifecycle events into remote session, transcript, and turn state while rejecting stale capabilities. */
export class SdkSessionProjection implements SdkSessionProjectionPort {
  private readonly issuer = new RemoteSessionIssuer();
  private sessionStartedAt: number | null = null;
  private readonly transcriptLog = new TranscriptEventLog();
  private readonly deliveredUserEventIds = new Map<string, { clientMessageId: string; eventId: string }[]>();
  /** Ingress idempotency guard (story-extension-user-message-ingress-
   *  idempotency): `clientMessageId`s already delivered in each session, so a
   *  duplicate `user_message` frame (reconnect flush, relay fan-out, app
   *  re-send) does NOT re-invoke the agent. Keyed by sessionId, cleared on
   *  session replacement (same lifecycle as `transcriptLog`). */
  private readonly deliveredUserMessageIds = new Map<string, Set<string>>();
  private lastTranscriptUserId: string | null = null;
  private epoch = 0;
  private commandCtx: ExtensionCommandContext | null = null;
  private eventCtx: ExtensionContext | null = null;
  private messageApi: AgentMessageApi | null = null;
  private actionApi: FreshActionApi | null = null;
  private transcriptEntryApi: TranscriptEntryApi | null = null;
  private transcriptPersistence: TranscriptEventPersistence | null = null;
  private turn: TurnSnapshot = initialTurnSnapshot();
  private roomId: string | null = null;
  private readonly meshIngressLimits: MeshIngressLimits;
  private pendingMeshMessages: PendingMeshMessage[] = [];
  private readonly pendingMeshByPeer = new Map<string, PeerMeshAccounting>();
  private pendingMeshBytes = 0;
  private agentRunActive = false;
  private meshFlushScheduled = false;

  constructor(private readonly opts: SdkSessionProjectionOptions) {
    this.meshIngressLimits = { ...DEFAULT_MESH_INGRESS_LIMITS, ...opts.meshIngressLimits };
  }

  /** Set the room id for delivery-log correlation. Called when `_myRoomId` is
   *  bound (the projection is constructed before the room is known). */
  setRoomId(roomId: string | null): void {
    this.roomId = roomId;
  }

  bindApi(pi: ExtensionAPI): void {
    this.bindCapabilities(pi);
    if (!this.agentRunActive) this.scheduleMeshMessageFlush();
    this.opts.outputs.deliveryDebugLog?.log({
      tag: "message_api_armed",
      via: "factory",
      sessionIdTail: this.issuer.current() ?? "unknown",
      roomId: this.roomId ?? undefined,
    });
  }

  bindCommandContext(ctx: ExtensionCommandContext): void {
    this.commandCtx = ctx;
    this.bindCapabilities(ctx);
    this.opts.outputs.deliveryDebugLog?.log({
      tag: "command_ctx",
      armed: true,
      via: "slash",
      roomId: this.roomId ?? undefined,
    });
  }

  bindSessionContext(ctx: ExtensionContext, opts?: { subagentChild?: boolean }): void {
    // A child subagent session re-binds the parent's extensions
    // (`@gotgenes/pi-subagents` `create-subagent-session.ts:233`), so the
    // child's `session_start` fires here too. The child carries a FRESH
    // session id (`SessionManager.newSession` → new uuidv7). If we let the
    // child's `session_start` run the usual side effects, three things break
    // (confirmed by live capture 2026-07-07, /tmp/outpost-pi-debug-send.jsonl):
    //   (a) `issuer.capture(childCtx)` overwrites the parent's session id →
    //       subsequent parent broadcasts are stamped with the CHILD id
    //       (capture showed parent frames after the window carrying the
    //       child id → app session-gate drops them as session_mismatch);
    //   (b) `captureRemoteSession` publishes `room_meta_update({session_id:
    //       childId})` → the app's `_onRoomsChanged` → `activate()` rebinds to
    //       the child's empty session box → mobile chatlog WIPED (the single
    //       room_meta_update at gateActive=true is the wipe);
    //   (c) `backfillTranscriptFromSessionManager(childCtx)` stamps parent-seeded
    //       history under the child's id into the transcript log.
    // The `subagentChild` option preserves that suppression for explicit
    // projection callers and focused tests. The production composition root
    // now denies real children during coordinator activation, before its
    // session-context port can reach this method, so index.ts always takes the
    // full owner-binding path. Capability rebinds (`bindCapabilities`) remain
    // available to explicit child callers and do not touch the phone.
    const suppressChildSideEffects = opts?.subagentChild === true;
    this.eventCtx = ctx;
    // Capture the fresh session id BEFORE any backfill. `session_start` fires
    // for startup/new/fork/reload/resume, and `clearStaleContexts` does NOT
    // clear the issuer — so without this the prior session's id would still be
    // current and the backfill below would stamp events with the stale id,
    // leaving them unreachable to `forSession(currentId)` (the blank-history
    // bug). The index.ts wrapper re-captures via `_captureRemoteSession`
    // (idempotent) and publishes room_meta; capturing here is the ordering fix.
    // SKIPPED for a child subagent session_start (suppressChildSideEffects) so
    // the parent's session id is preserved.
    if (!suppressChildSideEffects) {
      this.issuer.capture(ctx);
    }
    // Additive, not replacing: the `session_start` ctx (built by
    // `ExtensionRunner.createContext()` in the SDK) carries ui/cwd/abort/compact
    // but NOT sendMessage/sendUserMessage — only `ExtensionAPI` (the factory
    // `pi`) and `ReplacedSessionContext` carry those. Replacing here would null
    // the valid `messageApi` armed at factory init by `bindApi(pi)` on every
    // session_start (including startup), making `sendPiMessage` return false and
    // silently dropping user-facing renders like the pair-code QR. Additive
    // `bindCapabilities` only rebinds when the ctx actually carries the message
    // API (a `withSession` ReplacedSessionContext), which is the intended path;
    // otherwise the `pi`-armed binding is preserved. `bindReplacementContext`
    // still calls `replaceSessionCapabilities` to drop a stale `pi`.
    this.bindCapabilities(ctx);
    // SKIPPED for a child subagent session_start: the child's SessionManager is
    // separate and would stamp parent-seeded history under the child's id.
    if (!suppressChildSideEffects) {
      this.backfillTranscriptFromSessionManager(ctx);
    }
  }

  /**
   * Hydrate transcript authority from the SDK's active, compaction-aware branch.
   *
   * SDK messages remain untouched and authoritative for LLM context. This read
   * only reconciles the extension-owned transcript: validated Outpost-Pi custom
   * entries win matching facts, while SDK message projection remains the mixed-
   * version and corrupt-entry fallback.
   */
  private backfillTranscriptFromSessionManager(ctx: ExtensionContext): void {
    const sm = (ctx as { sessionManager?: unknown }).sessionManager;
    if (!sm || typeof sm !== "object") return;
    const build = (sm as { buildContextEntries?: () => unknown }).buildContextEntries;
    if (typeof build !== "function") return;
    let entries: SdkTranscriptContextEntry[];
    try {
      const resolved = build.call(sm);
      entries = Array.isArray(resolved) ? resolved as SdkTranscriptContextEntry[] : [];
    } catch {
      // A transcript read cannot block session_start or mutate SDK context.
      return;
    }
    if (entries.length === 0) return;
    const sessionId = this.issuer.current() ?? this.currentRemoteSessionId(ctx);
    const mapped = reconcileTranscriptContextEntries({ sessionId, entries });

    // Preserve live app identity across an in-process reload when the SDK-only
    // fallback synthesizes sync_<ts>. Durable app entries already carry their
    // canonical id and bypass this compatibility reconciliation.
    const existingUsers = this.indexExistingUserEventsByContent(sessionId);
    const reconciled = mapped.map((event): TranscriptEvent => {
      if (event.kind !== "user_confirmed" || !event.clientMessageId.startsWith("sync_")) return event;
      const key = transcriptUserContentSignature(event.text, event.images);
      const claims = existingUsers.get(key);
      const existing = claims?.shift();
      if (!existing) return event;
      if (claims?.length === 0) existingUsers.delete(key);
      return { ...event, clientMessageId: existing.clientMessageId, eventId: existing.eventId };
    });
    this.transcriptLog.hydrate(reconciled);
    this.recomputeLastTranscriptUserId();
  }

  private indexExistingUserEventsByContent(
    sessionId: string,
  ): Map<string, { clientMessageId: string; eventId: string }[]> {
    const out = new Map<string, { clientMessageId: string; eventId: string }[]>();
    for (const event of this.transcriptLog.forSession(sessionId)) {
      if (event.kind !== "user_confirmed") continue;
      const key = transcriptUserContentSignature(event.text, event.images);
      const claims = out.get(key) ?? [];
      claims.push({ clientMessageId: event.clientMessageId, eventId: event.eventId });
      out.set(key, claims);
    }
    return out;
  }

  bindReplacementContext(ctx: ActionCtx): RemoteSessionId {
    this.commandCtx = ctx as unknown as ExtensionCommandContext;
    this.eventCtx = ctx as unknown as ExtensionContext;
    this.replaceSessionCapabilities(ctx);
    const sessionId = this.captureRemoteSession(ctx);
    // The withSession re-arm path (mobile `session_new`). Emits the
    // `message_api_armed { via: "withSession" }` + `command_ctx { armed:
    // true, via: "withSession" }` evidence the story needs to prove mobile
    // recovery (distinct from the factory `/reload` re-arm in `bindApi`).
    this.opts.outputs.deliveryDebugLog?.log({
      tag: "message_api_armed",
      via: "withSession",
      sessionIdTail: idTail(sessionId),
      roomId: this.roomId ?? undefined,
    });
    this.opts.outputs.deliveryDebugLog?.log({
      tag: "command_ctx",
      armed: true,
      via: "withSession",
      roomId: this.roomId ?? undefined,
    });
    return sessionId;
  }

  clearApiBindings(): void {
    this.messageApi = null;
    this.actionApi = null;
    this.clearTranscriptPersistence();
  }

  clearStaleContexts(): void {
    this.epoch += 1;
    this.commandCtx = null;
    this.eventCtx = null;
    this.messageApi = null;
    this.actionApi = null;
    this.clearTranscriptPersistence();
    this.agentRunActive = false;
    this.meshFlushScheduled = false;
    this.clearPendingMeshMessages();
    this.opts.outputs.deliveryDebugLog?.log({
      tag: "message_api_null",
      reason: "shutdown",
      roomId: this.roomId ?? undefined,
    });
    this.opts.outputs.deliveryDebugLog?.log({
      tag: "command_ctx",
      armed: false,
      via: "slash",
    });
  }

  captureRemoteSession(ctx: unknown): RemoteSessionId {
    const sessionId = this.issuer.capture(ctx);
    this.opts.outputs.publishRoomMeta({ session_id: sessionId });
    return sessionId;
  }

  currentRemoteSessionId(ctx?: unknown): RemoteSessionId {
    return this.issuer.currentOrCapture(ctx ?? this.eventCtx ?? this.commandCtx ?? undefined);
  }

  currentSessionMessage<T extends object>(msg: T): T & { session_id: RemoteSessionId } {
    return { ...msg, session_id: this.currentRemoteSessionId() };
  }

  currentSessionIdForTest(): RemoteSessionId | null {
    return this.issuer.current();
  }

  setSessionIdForTest(id: string | null): void {
    if (id === null) this.issuer.clear();
    else this.issuer.capture({ sessionManager: { getSessionId: () => id } });
  }

  sessionStartedAtValue(): number | null {
    return this.sessionStartedAt;
  }

  sessionStartedAtOrNow(now = Date.now()): number {
    return this.sessionStartedAt ?? now;
  }

  setSessionStartedAt(ts: number | null): void {
    this.sessionStartedAt = ts;
  }

  ensureSessionStarted(now = Date.now()): number {
    if (this.sessionStartedAt === null) this.sessionStartedAt = now;
    return this.sessionStartedAt;
  }

  /**
   * Record a canonical transcript event before publishing its live projection.
   *
   * Persistence is attempted before the event enters the authoritative
   * in-memory log. The result is `recorded` after a successful append,
   * `duplicate` for an existing `(sessionId, eventId)`, `unavailable` when the
   * current SDK session has no writer, or `failed` when validation or append
   * fails; only the first two outcomes authorize visibility.
   */
  recordDurableTranscriptEvent(event: TranscriptEvent): TranscriptRecordResult {
    return this.transcriptLog.record(event);
  }

  /**
   * Look up the canonical timestamp owned by a recorded transcript event.
   *
   * The identity lookup is scoped to `(sessionId, eventId)`; an omitted session
   * uses the current SDK session. `undefined` means no matching durable or
   * hydrated event is known yet, not that the event has timestamp zero.
   */
  recordedTranscriptTs(eventId: string, sessionId = this.currentRemoteSessionId()): number | undefined {
    return this.transcriptLog.recordedTsFor(sessionId, eventId);
  }

  /** Report whether the current SDK lifecycle has a durable transcript writer. */
  hasTranscriptPersistence(): boolean {
    return this.transcriptLog.hasPersistence();
  }

  /**
   * Reserve app identity for the next matching SDK user message.
   *
   * The returned rollback removes only this still-pending reservation and is
   * a no-op after consumption or session reset.
   */
  rememberDeliveredUserEvent(
    text: string,
    images: readonly { data: string; mime: string }[] | undefined,
    clientMessageId: string,
    eventId: string,
  ): () => void {
    const key = transcriptUserContentSignature(text, images);
    const entry = { clientMessageId, eventId };
    const existing = this.deliveredUserEventIds.get(key) ?? [];
    existing.push(entry);
    this.deliveredUserEventIds.set(key, existing);
    return () => {
      const pending = this.deliveredUserEventIds.get(key);
      if (!pending) return;
      const index = pending.indexOf(entry);
      if (index < 0) return;
      pending.splice(index, 1);
      if (pending.length === 0) this.deliveredUserEventIds.delete(key);
    };
  }

  /** Ingress idempotency guard (story-extension-user-message-ingress-
   *  idempotency): was `clientMessageId` already delivered in `sessionId`?
   *  Checked at the top of `_deliverUserMessage` so a duplicate frame does
   *  not re-invoke the agent. */
  wasUserMessageDelivered(sessionId: string, clientMessageId: string): boolean {
    return this.deliveredUserMessageIds.get(sessionId)?.has(clientMessageId) ?? false;
  }

  /** Record that `clientMessageId` was delivered in `sessionId`. Called from
   *  `_confirmUserDelivery` after the agent accepts the message, so a later
   *  duplicate frame is suppressed. */
  recordDeliveredUserMessageId(sessionId: string, clientMessageId: string): void {
    (this.deliveredUserMessageIds.get(sessionId) ?? this.deliveredUserMessageIds.set(sessionId, new Set<string>()).get(sessionId)!).add(clientMessageId);
  }

  /** Record current SDK message facts durably before broadcasting transcript visibility. */
  recordSdkMessageTranscriptEvents(message: SdkTranscriptMessage): void {
    const sessionId = this.currentRemoteSessionId();
    const ts = typeof message.timestamp === "number" ? message.timestamp : Date.now();
    if (message.role === "user") {
      const text = stringifyContent(message.content);
      const images = imagesFromContent(message.content);
      const matched = this.consumeDeliveredUserEvent(text, images);
      const producerTs = matched ? this.recordedTranscriptTs(matched.eventId) : undefined;

      // App delivery owns its timestamp. If message_end wins the race, consume
      // the reservation but wait for the delivery hook to record and publish.
      if (matched && producerTs === undefined && this.hasTranscriptPersistence()) return;

      const clientMessageId = matched?.clientMessageId ?? `sync_${ts}`;
      const canonicalTs = producerTs ?? ts;
      const eventId = matched?.eventId
        ?? deterministicTranscriptEventId(sessionId, "user_confirmed", clientMessageId);
      const recorded = this.transcriptLog.record({
        kind: "user_confirmed",
        eventId,
        sessionId,
        ts: canonicalTs,
        clientMessageId,
        text,
        ...(images.length > 0 ? { images } : {}),
      });
      if (recorded.status !== "recorded" && recorded.status !== "duplicate") return;
      this.lastTranscriptUserId = clientMessageId;
      this.opts.outputs.broadcast(this.currentSessionMessage({
        type: SERVER_MESSAGE_DISCRIMINATORS.user_input,
        id: clientMessageId,
        text,
        ts: this.recordedTranscriptTs(eventId) ?? canonicalTs,
        ...(images.length > 0 ? { images } : {}),
      }));
      return;
    }

    if (message.role !== "assistant") return;
    const content = Array.isArray(message.content) ? message.content : [];
    const usage = message.usage
      ? { input_tokens: message.usage.input ?? 0, output_tokens: message.usage.output ?? 0 }
      : undefined;
    for (const [blockIndex, raw] of content.entries()) {
      if (!raw || typeof raw !== "object") continue;
      const block = raw as { type?: string; text?: unknown };
      if (block.type !== "text") continue;
      const text = String(block.text ?? "");
      if (!text) continue;
      const messageId = `sync_${ts}:assistant:${blockIndex}`;
      const replyTo = this.lastTranscriptUserId ?? `sync_${ts}`;
      const eventId = deterministicTranscriptEventId(sessionId, "assistant_committed", messageId);
      const recorded = this.transcriptLog.record({
        kind: "assistant_committed",
        eventId,
        sessionId,
        ts,
        messageId,
        replyTo,
        text,
        ...(usage ? { usage } : {}),
      });
      if (recorded.status !== "recorded" && recorded.status !== "duplicate") continue;
      this.opts.outputs.broadcast(this.currentSessionMessage({
        type: SERVER_MESSAGE_DISCRIMINATORS.agent_message,
        in_reply_to: replyTo,
        text,
        ts: this.recordedTranscriptTs(eventId) ?? ts,
        message_id: messageId,
        ...(usage ? { usage } : {}),
      }));
    }
  }

  setPreDurableSdkMessagesForTest(msgs: unknown[]): void {
    this.clearTranscriptOnly();
    const sessionId = this.currentRemoteSessionId();
    this.transcriptLog.replace(reconcileTranscriptContextEntries({
      sessionId,
      entries: (msgs as SdkTranscriptMessage[]).map((message) => ({ type: "message", message })),
    }));
    this.recomputeLastTranscriptUserId();
  }

  setTranscriptEventsForTest(events: TranscriptEvent[]): void {
    this.deliveredUserEventIds.clear();
    this.transcriptLog.replace(events);
    this.recomputeLastTranscriptUserId();
  }

  getTranscriptEventsForTest(): TranscriptEvent[] {
    return [...this.transcriptLog.entries()];
  }

  /** Test-only: swap the delivery debug log so projection-side emits route to
   *  a fake. Mirrors the index.ts `_setDeliveryDebugLogForTest` accessor. */
  setDeliveryDebugLogForTest(log: DeliveryDebugLog): void {
    (this.opts.outputs as { deliveryDebugLog?: DeliveryDebugLog }).deliveryDebugLog = log;
  }

  buildSessionHistoryMessage(
    inReplyTo: string,
    limit: number | undefined,
  ): Extract<ServerMessage, { type: "session_history" }> {
    const serverLimit = syncLimit();
    const requested = limit ?? serverLimit;
    const effectiveLimit = Math.min(requested, serverLimit);

    const sessionId = this.currentRemoteSessionId();
    const projection = projectSessionHistory({
      sessionId,
      events: this.transcriptLog.forSession(sessionId),
      limit: effectiveLimit,
    });

    return this.currentSessionMessage({
      type: SERVER_MESSAGE_DISCRIMINATORS.session_history,
      in_reply_to: inReplyTo,
      session_started_at: this.sessionStartedAt ?? 0,
      events: projection.events,
      eos: true,
      truncated: projection.truncated,
    });
  }

  emptySessionHistoryMessage(inReplyTo: string): Extract<ServerMessage, { type: "session_history" }> {
    return this.currentSessionMessage({
      type: SERVER_MESSAGE_DISCRIMINATORS.session_history,
      in_reply_to: inReplyTo,
      session_started_at: this.sessionStartedAt ?? 0,
      events: [],
      eos: true,
      truncated: false,
    });
  }

  resetSessionForNew(inReplyTo: string): void {
    this.clearTranscriptOnly();
    this.sessionStartedAt = Date.now();
    this.opts.outputs.broadcast(this.emptySessionHistoryMessage(inReplyTo));
  }

  /** Mark the start of an SDK run so mesh ingress waits for the settled boundary. */
  markAgentRunStarted(): void {
    this.agentRunActive = true;
  }

  /** Flush one accepted mesh batch after retries, compaction, and continuations settle. */
  markAgentSettled(): void {
    this.agentRunActive = false;
    this.scheduleMeshMessageFlush();
  }

  /**
   * Admit one rendered mesh message under global and per-peer frame/byte limits.
   *
   * Accepted messages retain arrival order. Overflow rejects the newest frame
   * without evicting an accepted prefix.
   */
  enqueueMeshMessage(peerId: string, content: string): MeshIngressAdmission {
    const bytes = Buffer.byteLength(content, "utf8");
    const peer = this.pendingMeshByPeer.get(peerId) ?? { frames: 0, bytes: 0 };
    if (
      this.pendingMeshMessages.length >= this.meshIngressLimits.maxFrames
      || peer.frames >= this.meshIngressLimits.maxFramesPerPeer
    ) {
      return { accepted: false, reason: "frame_limit" };
    }
    if (
      bytes > this.meshIngressLimits.maxBytes - this.pendingMeshBytes
      || bytes > this.meshIngressLimits.maxBytesPerPeer - peer.bytes
    ) {
      return { accepted: false, reason: "byte_limit" };
    }

    this.pendingMeshMessages.push({ peerId, content, bytes });
    this.pendingMeshBytes += bytes;
    this.pendingMeshByPeer.set(peerId, { frames: peer.frames + 1, bytes: peer.bytes + bytes });
    if (!this.agentRunActive) this.scheduleMeshMessageFlush();
    return { accepted: true };
  }

  sendPiMessage(...args: Parameters<ExtensionAPI["sendMessage"]>): boolean {
    const api = this.messageApi;
    if (!api) return false;
    try {
      const delivered = api.sendMessage(...args);
      if (isPromiseLike(delivered)) {
        delivered.catch((err: unknown) => {
          if (isStaleContextError(err)) this.forget(api);
        });
      }
      return true;
    } catch (err) {
      if (isStaleContextError(err)) this.forget(api);
      return false;
    }
  }

  async wakeAgent(...args: Parameters<ExtensionAPI["sendUserMessage"]>): Promise<WakeAgentResult> {
    const api = this.messageApi;
    // The null-`messageApi` window immediately after a session replacement
    // (clearStaleContexts nulls it; bindApi re-arms on the next factory
    // invocation). Not a real delivery failure — the phone should tolerate it.
    if (!api) return { ok: false, detail: "agent session not bound yet", recoverable: true };
    try {
      await api.sendUserMessage(...args);
      return { ok: true };
    } catch (err) {
      const stale = isStaleContextError(err);
      if (stale) this.forget(api);
      // A stale ctx is recoverable: the message wasn't delivered to THIS pi's
      // agent, but a sibling pi may have handled it (cross-process fanout) or
      // the next session_start rebinds a working api and the phone retries.
      // Real delivery failures (malformed content, provider down at handoff)
      // are NOT recoverable and still surface as internal_error.
      return { ok: false, detail: err instanceof Error ? err.message : String(err), recoverable: stale };
    }
  }

  publishWorking(working: boolean): void {
    this.opts.outputs.publishRoomMeta({ working });
  }

  turnProjection(): TurnProjection {
    return projectTurn(this.turn);
  }

  currentTurnIdForTest(): string | null {
    return this.turnProjection().activeTurnId;
  }

  applyTurn(event: TurnEvent): TurnProjection {
    const before = this.turnProjection();
    this.turn = reduceTurn(this.turn, event);
    const after = this.turnProjection();
    this.publishTurnProjection(before, after);
    return after;
  }

  resetTurnSnapshot(): void {
    const before = this.turnProjection();
    this.turn = initialTurnSnapshot();
    this.publishTurnProjection(before, this.turnProjection());
  }

  recordOwnerAttached(peerId: string): void {
    this.applyTurn({ type: "peer_attached", target: { kind: "owner", id: peerId } });
  }

  queuedMessageState(): Extract<ServerMessage, { type: "queued_message_state" }> {
    const queued = this.turnProjection().queuedMessage;
    return queued
      ? this.currentSessionMessage({ type: SERVER_MESSAGE_DISCRIMINATORS.queued_message_state, id: queued.id, text: queued.text })
      : this.currentSessionMessage({ type: SERVER_MESSAGE_DISCRIMINATORS.queued_message_state });
  }

  broadcastQueuedMessageState(): void {
    this.opts.outputs.broadcast(this.queuedMessageState());
  }

  seedUserMessageTurn(input: {
    turnId: string;
    source: Exclude<TurnSource, "compaction">;
    shouldSteer: boolean;
  }): SeededUserTurn {
    const previous = this.turn;
    const seeded = !input.shouldSteer || this.turnProjection().activeTurnId === null;
    if (seeded) {
      this.applyTurn({
        type: "user_message_accepted",
        turnId: input.turnId,
        replyTo: input.turnId,
        source: input.source,
      });
    }
    return {
      seeded,
      rollback: () => {
        if (!seeded) return;
        const before = this.turnProjection();
        this.turn = previous;
        this.publishTurnProjection(before, this.turnProjection());
      },
    };
  }

  maybeDrainQueuedMessage(
    deliver: (message: Extract<ClientMessage, { type: "user_message" }>) => void | Promise<void>,
    onRejected: (
      message: Extract<ClientMessage, { type: "user_message" }>,
      error: unknown,
    ) => void,
  ): void {
    const projection = this.turnProjection();
    const queued = projection.queuedMessage;
    if (!queued || !projection.canDrainQueuedMessage) return;
    this.applyTurn({ type: "queued_message_clear" });
    this.broadcastQueuedMessageState();
    const message: Extract<ClientMessage, { type: "user_message" }> = this.currentSessionMessage({
      type: SERVER_MESSAGE_DISCRIMINATORS.user_message,
      id: queued.id,
      text: queued.text,
    });
    const delivery = deliver(message);
    if (isPromiseLike(delivery)) {
      delivery.catch((error: unknown) => onRejected(message, error));
    }
  }

  maybeSendLateAttachSessionSync(
    buildHistory: (inReplyTo: string) => Extract<ServerMessage, { type: "session_history" }>,
  ): void {
    const projection = this.turnProjection();
    if (!projection.canFlushLateAttachSync || projection.awaitingSyncTurnId === null) return;
    const history = buildHistory(projection.awaitingSyncTurnId);
    const activeTargets = new Map(this.opts.outputs.lateAttachTargets().map((entry) => [entry.peerId, entry.channel]));
    for (const target of projection.lateAttachSyncTargets) {
      if (target.kind !== "owner") continue;
      const channel = activeTargets.get(target.id);
      if (!channel) continue;
      try { this.opts.outputs.sendTo(channel, history); } catch { /* best-effort per late attach */ }
    }
    this.applyTurn({ type: "flush_late_attach_sync" });
  }

  handleClientMessage(sender: PeerChannel, message: ClientMessage): void | Promise<void> {
    return this.opts.outputs.handleClientMessage(sender, message);
  }

  currentEpoch(): number {
    return this.epoch;
  }

  commandContext(): ExtensionCommandContext | null {
    return this.commandCtx;
  }

  sessionContext(): ExtensionContext | null {
    return this.eventCtx;
  }

  messageApiBinding(): AgentMessageApi | null {
    return this.messageApi;
  }

  currentActionPi(action: "model_set" | "thinking_set"): ActionPi | null {
    const api = this.actionApi;
    if (!api) return null;
    if (action === "model_set" && typeof api.setModel !== "function") return null;
    if (action === "thinking_set" && typeof api.setThinkingLevel !== "function") return null;
    return this.wrapActionPi(api);
  }

  freshActionCtx(): ActionCtx | null {
    const ctx = this.eventCtx ?? this.commandCtx;
    return ctx ? this.wrapActionCtx(ctx as unknown as ActionCtx) : null;
  }

  freshCommandActionCtx(): ActionCtx | null {
    return this.commandCtx ? this.wrapActionCtx(this.commandCtx as unknown as ActionCtx) : null;
  }

  forgetStaleBinding(value: unknown): void {
    if (value === this.commandCtx) this.commandCtx = null;
    if (value === this.eventCtx) this.eventCtx = null;
    if (value === this.messageApi) {
      this.messageApi = null;
      this.opts.outputs.onStaleMessageApi?.(value as AgentMessageApi);
    }
    if (value === this.actionApi) this.actionApi = null;
    if (value === this.transcriptEntryApi) this.clearTranscriptPersistence();
  }

  private publishTurnProjection(before: TurnProjection, after: TurnProjection): void {
    if (before.working === after.working) return;
    this.publishWorking(after.working);
  }

  private scheduleMeshMessageFlush(): void {
    if (
      this.meshFlushScheduled
      || this.agentRunActive
      || this.pendingMeshMessages.length === 0
      || !this.messageApi
    ) return;
    this.meshFlushScheduled = true;
    const generation = this.epoch;
    queueMicrotask(() => {
      if (generation !== this.epoch) return;
      if (this.agentRunActive || !this.messageApi || this.pendingMeshMessages.length === 0) {
        this.meshFlushScheduled = false;
        return;
      }

      // Keep the admitted prefix and all accounting live until the SDK accepts
      // the handoff. New ingress may append behind it, but cannot bypass its
      // frame/byte budget or start a concurrent flush.
      const batch = this.pendingMeshMessages.slice();
      const content = batch.map((entry) => entry.content).join("\n\n---\n\n");
      const api = this.messageApi;
      const handoffSucceeded = (): void => {
        if (generation !== this.epoch) return;
        this.removePendingMeshBatch(batch);
        this.meshFlushScheduled = false;
        this.scheduleMeshMessageFlush();
      };
      const handoffFailed = (error: unknown): void => {
        if (generation !== this.epoch) return;
        const stale = isStaleContextError(error);
        if (stale) {
          this.forget(api);
          // A stale SDK context cannot safely retry this session's accepted
          // batch. Evict that prefix while preserving messages appended later
          // for a fresh binding.
          this.removePendingMeshBatch(batch);
        }
        // Non-stale failures retain the entire accounted prefix. The next
        // agent_settled boundary retries it; no failure loop is self-scheduled.
        this.meshFlushScheduled = false;
        this.opts.outputs.onMeshDeliveryFailure?.(stale ? "stale_session" : "send_failed");
      };

      try {
        const delivery = api.sendMessage(
          { customType: "outpost-pi:mesh-message", content, display: true },
          { triggerTurn: true, deliverAs: "followUp" },
        );
        if (isPromiseLike(delivery)) {
          delivery.then(handoffSucceeded, handoffFailed);
        } else {
          handoffSucceeded();
        }
      } catch (error) {
        handoffFailed(error);
      }
    });
  }

  private removePendingMeshBatch(batch: readonly PendingMeshMessage[]): void {
    this.pendingMeshMessages.splice(0, batch.length);
    for (const entry of batch) {
      this.pendingMeshBytes -= entry.bytes;
      const peer = this.pendingMeshByPeer.get(entry.peerId);
      if (!peer) continue;
      const frames = peer.frames - 1;
      const bytes = peer.bytes - entry.bytes;
      if (frames === 0) this.pendingMeshByPeer.delete(entry.peerId);
      else this.pendingMeshByPeer.set(entry.peerId, { frames, bytes });
    }
  }

  private clearPendingMeshMessages(): void {
    this.pendingMeshMessages = [];
    this.pendingMeshBytes = 0;
    this.pendingMeshByPeer.clear();
  }

  private bindCapabilities(value: unknown): void {
    if (isAgentMessageApi(value)) this.messageApi = value;
    if (isFreshActionApi(value)) this.actionApi = value;
    if (isTranscriptEntryApi(value)) this.bindTranscriptPersistence(value);
  }

  private replaceSessionCapabilities(value: unknown): void {
    this.messageApi = isAgentMessageApi(value) ? value : null;
    this.actionApi = isFreshActionApi(value) ? value : null;
    if (isTranscriptEntryApi(value)) this.bindTranscriptPersistence(value);
    else this.clearTranscriptPersistence();
  }

  private bindTranscriptPersistence(api: TranscriptEntryApi): void {
    const persistence: TranscriptEventPersistence = {
      append: (event) => {
        try {
          api.appendEntry(TRANSCRIPT_EVENT_CUSTOM_TYPE, encodeDurableTranscriptEventV1(event));
        } catch (error) {
          if (isStaleContextError(error) && api === this.transcriptEntryApi) {
            this.transcriptEntryApi = null;
            this.transcriptPersistence = null;
            this.transcriptLog.unbindPersistence(persistence);
          }
          throw error;
        }
      },
    };
    this.transcriptEntryApi = api;
    this.transcriptPersistence = persistence;
    this.transcriptLog.bindPersistence(persistence);
  }

  private clearTranscriptPersistence(): void {
    const persistence = this.transcriptPersistence;
    this.transcriptEntryApi = null;
    this.transcriptPersistence = null;
    if (persistence) this.transcriptLog.unbindPersistence(persistence);
    else this.transcriptLog.unbindPersistence();
  }

  private forget(api: AgentMessageApi): void {
    if (api !== this.messageApi) return;
    this.messageApi = null;
    if (api === this.actionApi) this.actionApi = null;
    if ((api as unknown) === this.transcriptEntryApi) this.clearTranscriptPersistence();
    this.opts.outputs.onStaleMessageApi?.(api);
    this.opts.outputs.deliveryDebugLog?.log({
      tag: "message_api_null",
      reason: "stale",
      roomId: this.roomId ?? undefined,
    });
  }

  private forgetActionApi(api: FreshActionApi): void {
    if (api === this.actionApi) this.actionApi = null;
    if (api === this.transcriptEntryApi) this.clearTranscriptPersistence();
    if (api === this.messageApi) {
      this.messageApi = null;
      this.opts.outputs.onStaleMessageApi?.(api as AgentMessageApi);
    }
  }

  private wrapActionPi(api: FreshActionApi): ActionPi {
    return {
      setModel: async (model: SdkModelLike) => {
        if (typeof api.setModel !== "function") throw new Error("Pi model API unavailable for the current session");
        try {
          return await api.setModel(model);
        } catch (err) {
          if (isStaleContextError(err)) this.forgetActionApi(api);
          throw err;
        }
      },
      setThinkingLevel: (level: ThinkingLevel) => {
        if (typeof api.setThinkingLevel !== "function") throw new Error("Pi thinking API unavailable for the current session");
        try {
          api.setThinkingLevel(level);
        } catch (err) {
          if (isStaleContextError(err)) this.forgetActionApi(api);
          throw err;
        }
      },
    };
  }

  private wrapActionCtx(ctx: ActionCtx): ActionCtx | null {
    // Accessing guarded SDK getters (modelRegistry, compact, newSession,
    // getModel, ui, cwd, ...) on a STALE ctx throws a stale-context error
    // synchronously — and the `typeof ctx.X === "function"` / `ctx.modelRegistry`
    // accesses below happen OUTSIDE the per-method try/catch, so a stale ctx
    // here crashes pi (uncaught through the message router). Guard the whole
    // property-access sequence: on a stale ctx, forget the binding and return
    // null so callers degrade to "no action ctx available" instead of crashing.
    try {
      const wrapped: ActionCtx = {};
      if (typeof ctx.compact === "function") {
        wrapped.compact = (options?: object) => {
          try {
            return ctx.compact?.(options);
          } catch (err) {
            if (isStaleContextError(err)) this.forgetStaleBinding(ctx);
            throw err;
          }
        };
      }
      if (typeof ctx.newSession === "function") {
        wrapped.newSession = async (options) => {
          try {
            return await ctx.newSession!(options);
          } catch (err) {
            if (isStaleContextError(err)) this.forgetStaleBinding(ctx);
            throw err;
          }
        };
      }
      if (typeof ctx.getModel === "function") {
        wrapped.getModel = () => {
          try {
            return ctx.getModel?.();
          } catch (err) {
            if (isStaleContextError(err)) this.forgetStaleBinding(ctx);
            throw err;
          }
        };
      }
      if (ctx.modelRegistry) wrapped.modelRegistry = ctx.modelRegistry;
      return wrapped;
    } catch (err) {
      if (isStaleContextError(err)) {
        this.forgetStaleBinding(ctx);
        return null;
      }
      throw err;
    }
  }

  private consumeDeliveredUserEvent(
    text: string,
    images: readonly { data: string; mime: string }[] | undefined,
  ): { clientMessageId: string; eventId: string } | undefined {
    const key = transcriptUserContentSignature(text, images);
    const existing = this.deliveredUserEventIds.get(key);
    if (!existing || existing.length === 0) return undefined;
    const match = existing.shift();
    if (existing.length === 0) this.deliveredUserEventIds.delete(key);
    return match;
  }

  private clearTranscriptOnly(): void {
    this.transcriptLog.clear();
    this.deliveredUserEventIds.clear();
    this.deliveredUserMessageIds.clear();
    this.lastTranscriptUserId = null;
  }

  private recomputeLastTranscriptUserId(): void {
    const currentSessionEvents = this.transcriptLog.forSession(this.currentRemoteSessionId());
    const lastUser = [...currentSessionEvents].reverse().find((event) =>
      event.kind === "user_confirmed" || event.kind === "user_submitted"
    );
    this.lastTranscriptUserId = lastUser?.clientMessageId ?? null;
  }
}

import type { SessionHistoryEvent, Usage, WireImage } from "../protocol/types.js";
import { decodeDurableTranscriptEntry } from "./durable_transcript_event.js";
import type { TranscriptEvent } from "./transcript_event.js";

/** Describe the permissive SDK history shape accepted only at the legacy-to-canonical transcript boundary. */
export type LegacyAgentMessage = {
  role: "user" | "assistant" | "toolResult" | "compaction" | "compactionSummary" | string;
  content?: unknown;
  summary?: string;
  timestamp?: number;
  toolCallId?: string;
  toolName?: string;
  isError?: boolean;
  usage?: { input?: number; output?: number };
  tokensBefore?: number;
};

/** Return a bounded wire-history projection and whether earlier canonical events were omitted. */
export type SessionHistoryProjection = {
  events: SessionHistoryEvent[];
  truncated: boolean;
};

type ProjectSessionHistoryInput = {
  sessionId: string;
  events: readonly TranscriptEvent[];
  limit: number;
};

type LegacyAdapterInput = {
  sessionId: string;
  messages: readonly LegacyAgentMessage[];
};

/** Describe active SDK context entries consumed at the transcript backfill boundary. */
export type SdkTranscriptContextEntry =
  | { type: "message"; message: LegacyAgentMessage }
  | { type: "compaction"; summary: string; tokensBefore: number; timestamp: string }
  | { type: "custom"; customType: string; data?: unknown }
  | { type: string };


/** Append a canonical event unless its stable event id is already present. */
export function appendTranscriptEvent(
  events: readonly TranscriptEvent[],
  event: TranscriptEvent,
): TranscriptEvent[] {
  if (events.some((candidate) => candidate.eventId === event.eventId)) return [...events];
  return [...events, event];
}

/** Project one session's canonical events to a bounded, deduplicated wire history. */
export function projectSessionHistory(input: ProjectSessionHistoryInput): SessionHistoryProjection {
  const deduped = dedupeTranscriptEvents(input.events)
    .filter((event) => event.sessionId === input.sessionId);
  const allEvents = transcriptEventsToSessionHistory(deduped);
  const effectiveLimit = Math.max(0, input.limit);
  const slice = effectiveLimit > 0 ? allEvents.slice(-effectiveLimit) : [];
  return {
    events: slice,
    truncated: allEvents.length > effectiveLimit,
  };
}

/** Map canonical transcript facts into replayable wire events while preserving their stable identities. */
export function transcriptEventsToSessionHistory(
  events: readonly TranscriptEvent[],
): SessionHistoryEvent[] {
  const out: SessionHistoryEvent[] = [];
  const seenUserIds = new Set<string>();
  const seenToolRequests = new Set<string>();
  const seenToolFinishes = new Set<string>();
  const seenAssistantMessages = new Set<string>();
  const seenCompactions = new Set<string>();

  for (const event of events) {
    switch (event.kind) {
      case "user_submitted":
      case "user_confirmed": {
        if (seenUserIds.has(event.clientMessageId)) break;
        seenUserIds.add(event.clientMessageId);
        out.push({
          ts: event.ts,
          type: "user_input",
          id: event.clientMessageId,
          text: event.text,
          ...(event.images && event.images.length > 0 ? { images: event.images } : {}),
          ...(event.kind === "user_confirmed" && event.streamingBehavior
            ? { streaming_behavior: event.streamingBehavior }
            : {}),
        });
        break;
      }
      case "assistant_committed": {
        if (seenAssistantMessages.has(event.messageId)) break;
        seenAssistantMessages.add(event.messageId);
        const usage = toWireUsage(event.usage);
        // Identity source (a): carry `message_id` (sync_<ts>:assistant:
        // <blockIndex>) on the replay event so the app's replay path can use
        // it as the stable key — multi-block assistant messages (same
        // in_reply_to+ts, different blocks) must NOT collide on the same
        // eventId. Mirrors the live agent_message broadcast. See
        // story-mobile-assistant-message-duplicated-live-replay decision 1.
        out.push({
          ts: event.ts,
          type: "agent_message",
          in_reply_to: event.replyTo,
          text: event.text,
          message_id: event.messageId,
          ...(usage ? { usage } : {}),
        });
        break;
      }
      case "tool_requested": {
        if (seenToolRequests.has(event.toolCallId)) break;
        seenToolRequests.add(event.toolCallId);
        out.push({
          ts: event.ts,
          type: "tool_request",
          tool_call_id: event.toolCallId,
          tool: event.tool,
          args: event.args,
        });
        break;
      }
      case "tool_finished": {
        if (seenToolFinishes.has(event.toolCallId)) break;
        seenToolFinishes.add(event.toolCallId);
        out.push(event.error !== undefined
          ? { ts: event.ts, type: "tool_result", tool_call_id: event.toolCallId, error: event.error }
          : { ts: event.ts, type: "tool_result", tool_call_id: event.toolCallId, result: event.result });
        break;
      }
      case "compaction_recorded": {
        if (seenCompactions.has(event.eventId)) break;
        seenCompactions.add(event.eventId);
        out.push({
          ts: event.ts,
          type: "compaction",
          summary: event.summary,
          tokens_before: event.tokensBefore ?? 0,
        });
        break;
      }
      case "user_failed":
      case "assistant_delta":
      case "assistant_done":
      case "provider_error":
        break;
    }
  }

  return out;
}

/** Convert permissive persisted SDK messages into canonical replay events for one remote session. */
export function mapLegacyAgentMessagesToTranscriptEvents(input: LegacyAdapterInput): TranscriptEvent[] {
  const events: TranscriptEvent[] = [];
  let lastUserId: string | null = null;
  for (const [messageIndex, message] of input.messages.entries()) {
    const ts = typeof message.timestamp === "number" ? message.timestamp : 0;
    if (message.role === "compaction" || message.role === "compactionSummary") {
      // `compaction` is the legacy SDK message_end shape (content holds the
      // summary). `compactionSummary` is what `buildSessionContext()` emits for
      // a persisted compaction entry (messages.js createCompactionSummaryMessage):
      // the summary lives on `.summary`, not `.content`. Both must map to the
      // same `compaction_recorded` transcript event so session_history can
      // replay a compaction that happened before the extension attached.
      const summary = message.role === "compactionSummary"
        ? (typeof message.summary === "string" ? message.summary : "")
        : (typeof message.content === "string" ? message.content : "");
      events.push({
        kind: "compaction_recorded",
        eventId: deterministicTranscriptEventId(input.sessionId, "compaction_recorded", String(ts)),
        sessionId: input.sessionId,
        ts,
        summary,
        tokensBefore: typeof message.tokensBefore === "number" ? message.tokensBefore : 0,
      });
    } else if (message.role === "user") {
      const clientMessageId = `sync_${ts}`;
      lastUserId = clientMessageId;
      const images = imagesFromContent(message.content);
      events.push({
        kind: "user_confirmed",
        eventId: deterministicTranscriptEventId(input.sessionId, "user_confirmed", clientMessageId),
        sessionId: input.sessionId,
        ts,
        clientMessageId,
        text: stringifyContent(message.content),
        ...(images.length > 0 ? { images } : {}),
      });
    } else if (message.role === "assistant") {
      const content = Array.isArray(message.content) ? message.content : [];
      const usage = message.usage ? { input_tokens: message.usage.input ?? 0, output_tokens: message.usage.output ?? 0 } : undefined;
      for (const [blockIndex, raw] of content.entries()) {
        if (!raw || typeof raw !== "object") continue;
        const block = raw as { type?: string; text?: unknown; id?: unknown; name?: unknown; arguments?: unknown };
        if (block.type === "text") {
          const text = String(block.text ?? "");
          if (!text) continue;
          const messageId = `sync_${ts}:assistant:${blockIndex}`;
          events.push({
            kind: "assistant_committed",
            eventId: deterministicTranscriptEventId(input.sessionId, "assistant_committed", messageId),
            sessionId: input.sessionId,
            ts,
            messageId,
            replyTo: lastUserId ?? `sync_${ts}`,
            text,
            ...(usage ? { usage } : {}),
          });
        } else if (block.type === "toolCall") {
          const toolCallId = String(block.id ?? `sync_${ts}:tool:${blockIndex}`);
          events.push({
            kind: "tool_requested",
            eventId: deterministicTranscriptEventId(input.sessionId, "tool_requested", toolCallId),
            sessionId: input.sessionId,
            ts,
            toolCallId,
            tool: String(block.name ?? ""),
            args: isRecord(block.arguments) ? block.arguments : {},
          });
        }
      }
    } else if (message.role === "toolResult") {
      const toolCallId = String(message.toolCallId ?? `sync_${ts}:tool-result:${messageIndex}`);
      const text = stringifyToolResult(message.content);
      events.push(message.isError
        ? {
            kind: "tool_finished",
            eventId: deterministicTranscriptEventId(input.sessionId, "tool_finished", toolCallId),
            sessionId: input.sessionId,
            ts,
            toolCallId,
            error: text,
          }
        : {
            kind: "tool_finished",
            eventId: deterministicTranscriptEventId(input.sessionId, "tool_finished", toolCallId),
            sessionId: input.sessionId,
            ts,
            toolCallId,
            result: text,
          });
    }
  }
  return events;
}

/**
 * Reconcile the SDK's active context branch into canonical transcript events.
 *
 * Valid durable entries are indexed before legacy messages are mapped so a
 * later execution-time custom entry can suppress an earlier SDK projection.
 * The SDK entry order still determines where each surviving event is replayed.
 */
export function mapSdkContextEntriesToTranscriptEvents(input: {
  sessionId: string;
  entries: readonly SdkTranscriptContextEntry[];
}): TranscriptEvent[] {
  const decodedByIndex = new Map<number, TranscriptEvent>();
  const durableEventIds = new Set<string>();
  const durableToolFacts = new Set<string>();
  const durableUserClaims = new Map<string, TranscriptEvent[]>();
  const durableUserClaimIds = new Set<string>();

  for (const [index, entry] of input.entries.entries()) {
    const decoded = decodeDurableTranscriptEntry(entry);
    if (decoded.status !== "decoded" || durableEventIds.has(decoded.event.eventId)) continue;
    const event = { ...decoded.event, sessionId: input.sessionId } as TranscriptEvent;
    decodedByIndex.set(index, event);
    durableEventIds.add(event.eventId);
    if (event.kind === "tool_requested" || event.kind === "tool_finished") {
      durableToolFacts.add(toolCollisionKey(event));
    } else if ((event.kind === "user_submitted" || event.kind === "user_confirmed")
      && !durableUserClaimIds.has(event.clientMessageId)) {
      durableUserClaimIds.add(event.clientMessageId);
      const signature = transcriptUserContentSignature(event.text, event.images);
      const claims = durableUserClaims.get(signature) ?? [];
      claims.push(event);
      durableUserClaims.set(signature, claims);
    }
  }

  const legacyByIndex = indexLegacyContextEvents(input.sessionId, input.entries);
  const output: TranscriptEvent[] = [];
  for (const [index, entry] of input.entries.entries()) {
    const durable = decodedByIndex.get(index);
    if (durable) {
      output.push(durable);
      continue;
    }

    if (entry.type === "message") {
      for (const event of legacyByIndex.get(index) ?? []) {
        if (!isClaimedByDurable(event, durableEventIds, durableToolFacts, durableUserClaims)) {
          output.push(event);
        }
      }
      continue;
    }

    if (entry.type === "compaction" && isRecord(entry)) {
      const record = entry as Record<string, unknown>;
      const timestamp = typeof record["timestamp"] === "string" ? Date.parse(record["timestamp"]) : Number.NaN;
      const ts = Number.isFinite(timestamp) ? timestamp : 0;
      const event: TranscriptEvent = {
        kind: "compaction_recorded",
        eventId: deterministicTranscriptEventId(input.sessionId, "compaction_recorded", String(ts)),
        sessionId: input.sessionId,
        ts,
        summary: typeof record["summary"] === "string" ? record["summary"] : "",
        tokensBefore: typeof record["tokensBefore"] === "number" ? record["tokensBefore"] : 0,
      };
      if (!durableEventIds.has(event.eventId)) output.push(event);
    }
  }
  return output;
}

/** Produce the content key used for one-for-one app-user reconciliation. */
export function transcriptUserContentSignature(
  text: string,
  images: readonly { data: string; mime: string }[] | undefined,
): string {
  return JSON.stringify({ text, images: images ?? [] });
}

function indexLegacyContextEvents(
  sessionId: string,
  entries: readonly SdkTranscriptContextEntry[],
): Map<number, TranscriptEvent[]> {
  const messages: LegacyAgentMessage[] = [];
  const sources: number[] = [];
  for (const [index, entry] of entries.entries()) {
    if (entry.type !== "message" || !("message" in entry)) continue;
    messages.push(entry.message);
    sources.push(index);
  }
  const mapped = mapLegacyAgentMessagesToTranscriptEvents({ sessionId, messages });
  const bySource = new Map<number, TranscriptEvent[]>();
  let cursor = 0;
  for (const [messageIndex, message] of messages.entries()) {
    const count = projectedEventCount(message);
    bySource.set(sources[messageIndex]!, mapped.slice(cursor, cursor + count));
    cursor += count;
  }
  return bySource;
}

function projectedEventCount(message: LegacyAgentMessage): number {
  if (message.role === "user" || message.role === "toolResult"
    || message.role === "compaction" || message.role === "compactionSummary") return 1;
  if (message.role !== "assistant" || !Array.isArray(message.content)) return 0;
  let count = 0;
  for (const raw of message.content) {
    if (!raw || typeof raw !== "object") continue;
    const block = raw as { type?: string; text?: unknown };
    if (block.type === "toolCall" || (block.type === "text" && String(block.text ?? "") !== "")) count++;
  }
  return count;
}

function isClaimedByDurable(
  event: TranscriptEvent,
  durableEventIds: ReadonlySet<string>,
  durableToolFacts: ReadonlySet<string>,
  durableUserClaims: Map<string, TranscriptEvent[]>,
): boolean {
  if (event.kind === "tool_requested" || event.kind === "tool_finished") {
    return durableToolFacts.has(toolCollisionKey(event));
  }
  if (event.kind === "user_submitted" || event.kind === "user_confirmed") {
    const signature = transcriptUserContentSignature(event.text, event.images);
    const claims = durableUserClaims.get(signature);
    if (claims && claims.length > 0) {
      claims.shift();
      if (claims.length === 0) durableUserClaims.delete(signature);
      return true;
    }
  }
  return durableEventIds.has(event.eventId);
}

function toolCollisionKey(
  event: Extract<TranscriptEvent, { kind: "tool_requested" | "tool_finished" }>,
): string {
  return `${event.kind}\u0000${event.toolCallId}`;
}

/** Extract text content from a legacy SDK content value, ignoring non-text blocks. */
export function stringifyContent(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .map((block) => {
      if (!block || typeof block !== "object") return "";
      const typed = block as { type?: string; text?: unknown };
      return typed.type === "text" ? String(typed.text ?? "") : "";
    })
    .join("");
}

/** Normalize a legacy tool result into the text preserved by transcript replay. */
export function stringifyToolResult(value: unknown): string {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) return stringifyContent(value);
  if (value !== null && typeof value === "object") {
    const obj = value as { content?: unknown; text?: unknown };
    if (Array.isArray(obj.content)) return stringifyContent(obj.content);
    if (typeof obj.text === "string") return obj.text;
    try { return JSON.stringify(value); } catch { return ""; }
  }
  return value === null || value === undefined ? "" : String(value);
}

/** Extract wire-image attachments from legacy multimodal SDK content. */
export function imagesFromContent(content: unknown): WireImage[] {
  if (!Array.isArray(content)) return [];
  const out: WireImage[] = [];
  for (const block of content) {
    if (!block || typeof block !== "object") continue;
    const typed = block as { type?: string; data?: unknown; mimeType?: unknown };
    if (typed.type === "image" && typeof typed.data === "string" && typeof typed.mimeType === "string") {
      out.push({ data: typed.data, mime: typed.mimeType });
    }
  }
  return out;
}

/** Derive the stable event id shared by live delivery and replay for one session fact. */
export function deterministicTranscriptEventId(
  sessionId: string,
  kind: TranscriptEvent["kind"],
  stableKey: string,
): string {
  return `server:${sessionId}:${kind}:${stableKey}`;
}

function dedupeTranscriptEvents(events: readonly TranscriptEvent[]): TranscriptEvent[] {
  const seen = new Set<string>();
  const out: TranscriptEvent[] = [];
  for (const event of events) {
    if (seen.has(event.eventId)) continue;
    seen.add(event.eventId);
    out.push(event);
  }
  return out;
}

function toWireUsage(usage: Usage | undefined): Usage | undefined {
  if (!usage) return undefined;
  return {
    input_tokens: usage.input_tokens ?? 0,
    output_tokens: usage.output_tokens ?? 0,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

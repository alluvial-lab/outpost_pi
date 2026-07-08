/**
 * Delivery-path ring log — the extension half of cross-side observability.
 *
 * The phone has a persistent ring log (`debug/*.bin`); the relay has a file
 * sink + `env_id_tail` correlation. The extension — where `messageApi` goes
 * null, where `bindApi` re-arms, where `wakeAgent` decides delivered-vs-
 * recoverable — had NO persistent log of the delivery path. The existing
 * `audit.jsonl` (`session/broker.ts`) records cross-PC mesh routing, not the
 * phone→Pi delivery path the stuck-state bug lives on.
 *
 * This module is the missing third leg: a bounded in-memory ring + file,
 * gated behind `REMOTE_PI_DEBUG_LOG=1`, capturing the delivery-path state
 * transitions keyed by the same message `id` the phone (`msg-send`) and relay
 * (`env_id_tail`) use. Privacy: routing metadata + message `id` + outcome
 * reasons only — never message text, images, tool args, or `ct`.
 *
 * See `story-extension-delivery-path-ring-log` for the design.
 */

import { mkdirSync, appendFileSync, existsSync, readFileSync, truncateSync, statSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { homedir } from "node:os";
import { join } from "node:path";

// ── Tag + event registry (single source of truth) ───────────────────────────

export const DELIVERY_DEBUG_TAG = [
  "msg_received",
  "wake_outcome",
  "msg_delivered",
  "delivery_pending",
  "queue_drained",
  "queue_dropped",
  "message_api_armed",
  "message_api_null",
  "session_lifecycle",
  "command_ctx",
] as const;
export type DeliveryDebugTag = (typeof DELIVERY_DEBUG_TAG)[number];

/**
 * Typed diagnostic event. Each variant owns its allowed fields and its scrub
 * (full message bodies / image data / tool args / `ct` are NEVER fields). The
 * tag is an enum, not a free string — the registry IS the capture surface.
 * Mirrors the app ring log's `DebugEvent` discipline.
 */
export type DeliveryDebugEvent =
  | { tag: "msg_received"; id: string; source: "app" | "queued"; steer: boolean }
  | { tag: "wake_outcome"; id: string; ok: boolean; recoverable: boolean; detail: string; messageApiArmed: boolean }
  | { tag: "msg_delivered"; id: string; sessionIdTail: string }
  | { tag: "delivery_pending"; id: string; queueLen: number; ttlMs: number }
  | { tag: "queue_drained"; id: string; wakeOk: boolean }
  | { tag: "queue_dropped"; id: string; reason: string }
  | { tag: "message_api_armed"; via: "factory" | "withSession"; sessionIdTail: string }
  | { tag: "message_api_null"; reason: "stale" | "shutdown" | "replacement" }
  | { tag: "session_lifecycle"; reason: "startup" | "reload" | "new" | "resume" | "fork" | "quit"; sessionIdTail: string }
  | { tag: "command_ctx"; armed: boolean; via: "slash" | "withSession" };

/** Fields that must NEVER appear in a serialized event (privacy scrub). */
const FORBIDDEN_KEYS = new Set([
  "text", "images", "args", "result", "ct", "prompt", "body", "message", "content",
]);

/** Max encoded bytes per field value — a huge untrusted string can't evict the window. */
const MAX_FIELD_LEN = 256;
/** Bounded ring cap (encoded). Drop oldest on append. */
const MAX_RING_BYTES = 512 * 1024;
/** Routine-event flush debounce. */
const FLUSH_DEBOUNCE_MS = 2_000;

/** Critical events flush immediately (the diagnostic tail survives a crash). */
const IMMEDIATE_FLUSH_TAGS: ReadonlySet<DeliveryDebugTag> = new Set([
  "wake_outcome",
  "queue_dropped",
  "message_api_null",
  "session_lifecycle",
]);

// ── Port ────────────────────────────────────────────────────────────────────

/**
 * Delivery-path debug log. Early no-op when debug mode is OFF. When ON,
 * appends the event to the ring + schedules flush (immediate for critical
 * events, debounced for routine). Never throws.
 */
export interface DeliveryDebugLog {
  log(event: DeliveryDebugEvent): void;
}

/** No-op implementation (default when `REMOTE_PI_DEBUG_LOG` is unset). */
export const noopDeliveryDebugLog: DeliveryDebugLog = { log: () => {} };

// ── Adapter ─────────────────────────────────────────────────────────────────

/**
 * File-backed bounded ring. Mirrors the app `DebugLogImpl` discipline:
 * cap enforced on append, per-field length caps, critical-event immediate
 * flush, export reads from the file (source of truth), never throws.
 */
export class DeliveryDebugLogImpl implements DeliveryDebugLog {
  /** Dirty (not-yet-flushed) lines. The file is the source of truth; the ring
   * holds only lines added since the last flush. This separation prevents the
   * warm-from-file → re-append duplication bug: warmed/persisted lines are
   * never in the dirty ring, so a flush never re-writes them. */
  private readonly ring: string[] = [];
  private ringBytes = 0;
  private flushTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly filePath: string;

  constructor(filePath: string) {
    this.filePath = filePath;
    this.ensureDir();
  }

  log(event: DeliveryDebugEvent): void {
    let line: string;
    try {
      line = this.serialize(event);
    } catch {
      // Never break delivery on a serialization failure.
      return;
    }
    this.ring.push(line);
    this.ringBytes += line.length + 1;
    this.truncateRing();
    if (IMMEDIATE_FLUSH_TAGS.has(event.tag)) {
      this.flushNow();
    } else {
      this.scheduleFlush();
    }
  }

  /** Force-flush, then read the file (source of truth). Null when empty. */
  export(): string | null {
    this.flushNow();
    try {
      if (!existsSync(this.filePath)) return null;
      const data = readFileSync(this.filePath, "utf8");
      return data.length > 0 ? data : null;
    } catch {
      return null;
    }
  }

  /** Wipe ring + file. */
  clear(): void {
    this.ring.length = 0;
    this.ringBytes = 0;
    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
    try {
      if (existsSync(this.filePath)) truncateSync(this.filePath, 0);
    } catch { /* best-effort */ }
  }

  dispose(): void {
    this.flushNow();
  }

  // ── internal ──────────────────────────────────────────────────────────────

  private serialize(event: DeliveryDebugEvent): string {
    const record: Record<string, unknown> = { tag: event.tag, ts: new Date().toISOString() };
    for (const [k, v] of Object.entries(event)) {
      if (k === "tag") continue;
      if (FORBIDDEN_KEYS.has(k)) continue; // defensive — the typed variants never carry these
      record[k] = typeof v === "string" ? truncateField(v, MAX_FIELD_LEN) : v;
    }
    // Assert no forbidden keys leaked (defensive; the type system already forbids them).
    for (const key of Object.keys(record)) {
      if (FORBIDDEN_KEYS.has(key)) throw new Error(`forbidden key leaked: ${key}`);
    }
    return JSON.stringify(record);
  }

  private truncateRing(): void {
    while (this.ringBytes > MAX_RING_BYTES && this.ring.length > 1) {
      const dropped = this.ring.shift()!;
      this.ringBytes -= dropped.length + 1;
    }
  }

  private scheduleFlush(): void {
    if (this.flushTimer) return;
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null;
      this.flushNow();
    }, FLUSH_DEBOUNCE_MS);
  }

  private flushNow(): void {
    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
    if (this.ring.length === 0) return;
    const batch = this.ring.join("\n") + "\n";
    this.ring.length = 0;
    this.ringBytes = 0;
    try {
      this.ensureDir();
      appendFileSync(this.filePath, batch, "utf8");
      this.capFile();
    } catch {
      // Lost this batch — never break delivery. The ring will re-accumulate.
    }
  }

  private ensureDir(): void {
    try {
      mkdirSync(dirname(this.filePath), { recursive: true });
    } catch { /* best-effort */ }
  }

  /** Keep the persistent file bounded: when it exceeds 2× the ring cap,
   *  truncate to the most recent `MAX_RING_BYTES` of lines. The file is the
   *  export source of truth; an unbounded append-only file would grow
   *  without limit across a long-lived process. Best-effort — never throws. */
  private capFile(): void {
    try {
      if (!existsSync(this.filePath)) return;
      if (statSync(this.filePath).size < MAX_RING_BYTES * 2) return;
      const data = readFileSync(this.filePath, "utf8");
      const lines = data.split("\n").filter((l) => l.length > 0);
      const keep = lines.slice(-Math.floor(MAX_RING_BYTES / 80)); // ~80 chars/line heuristic
      writeFileSync(this.filePath, keep.join("\n") + "\n", "utf8");
    } catch { /* best-effort */ }
  }
}

// ── Factory ─────────────────────────────────────────────────────────────────

/**
 * Resolve the delivery debug log from the env. `REMOTE_PI_DEBUG_LOG=1` enables
 * a file-backed ring at `<REMOTE_PI_HOME | ~/.pi/remote>/debug/delivery.log`;
 * otherwise a no-op. Called once at module init (the extension is a
 * long-lived process; the log lives for its lifetime).
 */
export function createDeliveryDebugLog(): DeliveryDebugLog {
  if (process.env["REMOTE_PI_DEBUG_LOG"] !== "1") return noopDeliveryDebugLog;
  const root = process.env["REMOTE_PI_HOME"] || homedir();
  // When REMOTE_PI_HOME is unset, root is homedir(); place under ~/.pi/remote/
  // to match the rest of remote-pi's state (global_config.ts HOME_PI_REMOTE).
  const base = process.env["REMOTE_PI_HOME"] ? root : join(homedir(), ".pi", "remote");
  const filePath = join(base, "debug", "delivery.log");
  try {
    return new DeliveryDebugLogImpl(filePath);
  } catch {
    // Construction failure (e.g. unwritable path) → degrade to no-op.
    return noopDeliveryDebugLog;
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/** Truncate a string to `max` chars (head-preserving), appending an ellipsis
 *  if cut. Named `truncateField` (not `tail`) because it keeps the START of the
 *  value — the meaningful prefix of an error message — rather than the end. */
function truncateField(value: string, max: number): string {
  if (value.length <= max) return value;
  return value.slice(0, max - 1) + "…";
}

/** Last 8 chars of an id/session id, for correlation (matches relay `id_tail`). */
export function idTail(id: string): string {
  if (id.length <= 8) return id;
  return id.slice(-8);
}

import { Buffer } from "node:buffer";

/** Bounded retention policy for the mesh MCP inbox.
 *
 * Security contract (gate-security-mcp-inbox-unbounded): the MCP server
 * buffers inbound peer messages for polling-only Claude sessions that may
 * never drain. Without a ceiling, a compromised authorized peer can exhaust
 * the subprocess's memory with no Claude tool approval involved. The bound
 * is count AND bytes, enforced drop-oldest with a surfaced drop count, so
 * the drain output stays honest about what was shed. A single message
 * larger than the byte budget is rejected outright (counted as dropped) —
 * the honest reading of a byte ceiling.
 */

/** Retention limits for one MCP inbox. */
export interface InboxLimits {
  readonly maxMessages: number;
  readonly maxBytes: number;
}

export const INBOX_LIMITS: InboxLimits = {
  maxMessages: 1_000,
  maxBytes: 4 * 1024 * 1024,
};

/** UTF-8 byte size of a value's compact JSON serialization. Bytes, not
 *  string `.length` UTF-16 code units — the inbox ceiling is a memory bound,
 *  and multi-byte content under-counts ~2–3× with code units (a 6.3 MB
 *  Unicode message passes a “4 MiB” unit-based ceiling). */
export function jsonByteSize(value: unknown): number {
  return Buffer.byteLength(JSON.stringify(value), "utf8");
}

/** Minimal shape the drain renderer needs (mesh_server's IncomingMsg
 *  satisfies it structurally). */
export interface InboxMessageView {
  readonly from: string;
  readonly id: string;
  readonly re: string | null;
  readonly at: string;
  readonly body: unknown;
}

/** Render one drained message as a compact block. COMPACT by contract:
 *  pretty-printed JSON multiplies deep nesting combinatorially (300
 *  depth-2000 bodies ≈ 3.6 MB retained render to ~2.4 GB of indented
 *  text) — the drain response must stay linear in retained bytes. The
 *  model consumes this output; compact JSON is machine-readable. */
export function renderInboxMessage(m: InboxMessageView): string {
  return `[${m.at}] from=${m.from}${m.re ? ` re=${m.re}` : ""}\nid=${m.id}\n${JSON.stringify(m.body)}`;
}

/** Drop-oldest bounded queue with a surfaced drop count. */
export class BoundedInbox<T> {
  private entries: { item: T; size: number }[] = [];
  private bytes = 0;
  private _dropped = 0;

  constructor(
    private readonly sizeOf: (item: T) => number,
    private readonly limits: InboxLimits = INBOX_LIMITS,
  ) {}

  /** Number of retained messages (wake-edge and drain checks read this). */
  get length(): number {
    return this.entries.length;
  }

  /** Retained items in arrival order. */
  items(): T[] {
    return this.entries.map((e) => e.item);
  }

  /** First retained item matching `pred`, in arrival order. */
  find(pred: (item: T) => boolean): T | undefined {
    return this.entries.find((e) => pred(e.item))?.item;
  }

  /** True when any retained item matches `pred` (local-unread check). */
  some(pred: (item: T) => boolean): boolean {
    return this.entries.some((e) => pred(e.item));
  }

  /** Retain one message, shedding the OLDEST overflow (never the newest). */
  push(item: T): void {
    const size = this.sizeOf(item);
    if (size > this.limits.maxBytes) {
      this._dropped++;
      return;
    }
    this.entries.push({ item, size });
    this.bytes += size;
    while (this.entries.length > 1 &&
      (this.entries.length > this.limits.maxMessages || this.bytes > this.limits.maxBytes)) {
      const shed = this.entries.shift()!;
      this.bytes -= shed.size;
      this._dropped++;
    }
  }

  /** Remove and return everything retained; report and reset the drop count. */
  drain(): { items: T[]; dropped: number } {
    const items = this.items();
    const dropped = this._dropped;
    this.entries = [];
    this.bytes = 0;
    this._dropped = 0;
    return { items, dropped };
  }
}

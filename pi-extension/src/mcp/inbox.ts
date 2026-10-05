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

/** Drop-oldest bounded queue with a surfaced drop count. */
export class BoundedInbox<T> {
  private entries: { item: T; size: number }[] = [];
  private bytes = 0;
  private _dropped = 0;

  constructor(
    private readonly sizeOf: (item: T) => number,
    private readonly limits: InboxLimits = INBOX_LIMITS,
  ) {}

  /** Messages shed since the last drain (surfaced in drain output). */
  get dropped(): number {
    return this._dropped;
  }

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

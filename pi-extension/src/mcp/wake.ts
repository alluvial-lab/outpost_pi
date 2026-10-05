/** Wake-nudge shaping for the Claude Code development channel.
 *
 * The mesh MCP server pushes a `notifications/claude/channel` notification
 * when an inbound mesh message should start a turn on an otherwise idle
 * Claude Code session (launched with the dev-channels flag). Two contracts
 * live here, both shared with the server wiring in `mesh_server.ts`:
 *
 * - The nudge carries NO message body: `get_messages` stays the single
 *   authoritative drain surface. A full-body nudge would let the model reply
 *   without draining, leaving a stale inbox duplicate that resurfaces at the
 *   next turn boundary. The message id likewise comes from the drain.
 * - Wakes are edge-triggered (empty→non-empty inbox transition only) and
 *   rate-capped: a burst or broadcast wakes once, and two woken peers
 *   ping-ponging cannot exceed one wake per `minIntervalMs`. The cap never
 *   drops inbox messages — only additional wakes; a suppressed edge arms a
 *   deferred re-check so capped messages still surface (liveness).
 */

/** Minimum gap between wake notifications (loop/storm backstop). */
export const WAKE_MIN_INTERVAL_MS = 5_000;

/** True when a peer address is local — a bare `<cwd>@<name>` composed
 *  address, which always starts with `/`. Cross-PC addresses carry a
 *  `<pc>:` prefix and never do. Used for the local-only wake boundary:
 *  remote messages buffer for the next drain but never start turns. */
export function isLocalPeerAddress(from: string): boolean {
  return from.startsWith("/");
}

/** Build the channel-notification content for one inbound mesh message.
 *
 * `from` is untrusted wire data (any mesh peer, cross-PC included) and is
 * JSON-quoted so it cannot smuggle formatting or control characters into
 * the channel block the model reads. */
export function wakeNudgeContent(from: string): string {
  return (
    `📨 mesh message from ${JSON.stringify(from)} arrived — ` +
    `call get_messages to read it and reply (echo its id via re)`
  );
}

/** Edge-triggered, rate-capped wake decision for the inbox.
 *
 * Pure decision logic — no timers. The caller supplies `nowMs` (and wires
 * the deferred re-check timer in its own runtime), so the gate is fully
 * deterministic under test. */
export class WakeGate {
  private lastReleaseMs: number | null = null;

  constructor(private readonly minIntervalMs: number) {}

  /** Decide whether one inbound message wakes the session: true only on the
   *  empty→non-empty edge while the rate cap allows it. */
  onMessage(inboxLengthBefore: number, nowMs: number): boolean {
    if (inboxLengthBefore !== 0) return false;
    return this.release(nowMs);
  }

  /** Decide whether a deferred re-check (armed after a cap-suppressed edge)
   *  may wake now. The caller only invokes this after `retryAfterMs` elapses,
   *  so the cap is respected by construction. */
  onDeferredRecheck(nowMs: number): boolean {
    return this.release(nowMs);
  }

  /** Milliseconds until a deferred re-check can succeed, or null when the
   *  cap is already satisfied (no re-check pending). */
  retryAfterMs(nowMs: number): number | null {
    if (this.lastReleaseMs === null) return null;
    const remaining = this.minIntervalMs - (nowMs - this.lastReleaseMs);
    return remaining > 0 ? remaining : null;
  }

  private release(nowMs: number): boolean {
    if (this.lastReleaseMs !== null && nowMs - this.lastReleaseMs < this.minIntervalMs) {
      return false;
    }
    this.lastReleaseMs = nowMs;
    return true;
  }
}

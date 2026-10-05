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

import type { BoundedInbox } from "./inbox.js";

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

  /** Decide whether one wake-eligible inbound message may wake now: the
   *  rate cap is the gate's ONLY concern — edge semantics (local-only,
   *  wake-eligible unread) live in the coordinator, which calls this only
   *  on a genuine edge. */
  onMessage(nowMs: number): boolean {
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

// ── Wake coordinator (wiring seam) ───────────────────────────────────────

/** Full inbound message shape the coordinator retains and wakes on. */
export interface WakeMessage {
  readonly from: string;
  readonly body: unknown;
  readonly id: string;
  readonly re: string | null;
  readonly at: string;
}

/** Injected timer surface so coordinator scheduling is fake-time testable. */
export interface WakeScheduler {
  arm(delayMs: number, fire: () => void): void;
  cancel(): void;
}

export interface WakeCoordinator {
  /** Retain one inbound message and run the local-only edge-triggered wake
   *  decision (broker/system envelopes must be filtered by the caller). */
  onMessage(msg: WakeMessage): void;
  /** Called after a full inbox drain: re-arm the edge, cancel pending
   *  deferred re-checks (nothing left to wake about). */
  onDrain(): void;
}

/** Wire the wake policy to an inbox: LOCAL-PEER-ONLY, edge-triggered
 *  (wake-eligible empty→non-empty only), rate-capped, with a deferred
 *  liveness re-check when a cap suppresses the edge. Remote (`<pc>:`-prefixed
 *  non-E2E relay traffic) messages buffer for the next drain and never start
 *  turns; a local message arriving behind undrained remote ones still wakes
 *  (the edge tracks wake-ELIGIBLE unread state, not raw inbox length).
 *  Extracted from mesh_server so the wiring itself is unit-testable — the
 *  server script's module-load side effects resist direct import. */
export function createWakeCoordinator(
  inbox: BoundedInbox<WakeMessage>,
  gate: WakeGate,
  emit: (from: string) => void,
  scheduler: WakeScheduler,
  now: () => number = Date.now,
): WakeCoordinator {
  let armed = false;

  const armDeferred = (): void => {
    if (armed) return;
    const delay = gate.retryAfterMs(now());
    if (delay === null) return;
    armed = true;
    scheduler.arm(delay, () => {
      armed = false;
      // Liveness re-check: the inbox may have drained (nothing to wake
      // about) or still hold capped local messages that never woke anyone.
      // An early fire inside the cap window (clock skew) re-arms instead of
      // forcing a wake or dropping the pending work.
      const local = inbox.find((m) => isLocalPeerAddress(m.from));
      if (!local) return;
      if (gate.onDeferredRecheck(now())) emit(local.from);
      else armDeferred();
    });
  };

  return {
    onMessage(msg: WakeMessage): void {
      const hadLocalUnread = inbox.some((m) => isLocalPeerAddress(m.from));
      inbox.push(msg);
      if (!isLocalPeerAddress(msg.from)) return; // remote: buffer only
      if (hadLocalUnread) return; // not a wake-eligible edge
      if (gate.onMessage(now())) emit(msg.from);
      else armDeferred();
    },
    onDrain(): void {
      armed = false;
      scheduler.cancel();
    },
  };
}

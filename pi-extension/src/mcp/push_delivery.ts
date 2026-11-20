/** Push-turn delivery coordinator, transport port, and MCP server option/instruction helpers.
 *
 * Keeps push-delivered local peer envelopes strictly separate from the
 * `get_messages` inbox:
 * - Local peer envelopes (`isLocalPeerAddress`) enqueue into a dedicated
 *   bounded `pushQueue` and are pushed in rate-capped (`WakeGate`),
 *   UTF-8-byte-bounded batches through a pluggable `PushDeliveryTransport`
 *   (e.g. Claude `notifications/claude/channel`, or a future Antigravity
 *   sidecar UDS adapter). They NEVER enter `inbox` on the happy path.
 * - Cross-PC (`<pc>:`) and `_relay` envelopes go straight to `inbox` for
 *   `get_messages` and never trigger push delivery.
 * - Transport failures roll the unsent batch back into `inbox` (and oversized
 *   single envelopes move to `inbox` with a compact body-free pointer), so
 *   no message is silently dropped.
 */

import { Buffer } from "node:buffer";
import { type BoundedInbox, renderInboxMessage } from "./inbox.js";
import {
  type WakeCoordinator,
  type WakeGate,
  type WakeMessage,
  type WakeScheduler,
  isLocalPeerAddress,
} from "./wake.js";

/** Default UTF-8 byte ceiling per pushed batch (64 KiB — safely below Linux
 *  `MAX_ARG_STRLEN` 128 KiB for future CLI transports and compact for turns). */
export const PUSH_BATCH_MAX_BYTES = 64 * 1024;

/** CLI flag that opts into MCP push-turn delivery on `mesh_server` and the CLI wrapper. */
export const PUSH_DELIVER_CLI_FLAG = "--push-deliver" as const;

/** Environment variable that opts into MCP push-turn delivery when set to `"1"`. */
export const PUSH_DELIVER_ENV_VAR = "OUTPOST_PI_MCP_PUSH_DELIVER" as const;

const BATCH_SEP = "\n\n";
const BATCH_SEP_BYTES = Buffer.byteLength(BATCH_SEP, "utf8");

/** Transport port that delivers one formatted push-turn payload to the host
 *  harness. Rejecting signals a transport failure; the coordinator rolls the
 *  unsent batch back into `inbox` so `get_messages` can still drain it. */
export interface PushDeliveryTransport {
  deliver(content: string): Promise<void>;
}

/** Configuration for `createPushDeliveryCoordinator`. */
export interface PushDeliveryCoordinatorOptions {
  /** Buffer drained by `get_messages` (cross-PC, `_relay`, and fallbacks). */
  readonly inbox: BoundedInbox<WakeMessage>;
  /** Dedicated bounded queue for local peer envelopes awaiting push delivery. */
  readonly pushQueue: BoundedInbox<WakeMessage>;
  /** Shared rate-cap gate (typically `WAKE_MIN_INTERVAL_MS` = 5s). */
  readonly gate: WakeGate;
  /** Host-specific push transport adapter. */
  readonly transport: PushDeliveryTransport;
  /** Injected timer surface for deterministic fake-time testing. */
  readonly scheduler: WakeScheduler;
  /** Maximum UTF-8 bytes per pushed batch (defaults to `PUSH_BATCH_MAX_BYTES`). */
  readonly maxBatchBytes?: number;
  /** Clock function (defaults to `Date.now`). */
  readonly now?: () => number;
  /** Optional diagnostic callback invoked when `transport.deliver` rejects. */
  readonly onTransportError?: (err: unknown) => void;
}

/** Header prepended to a pushed batch so the receiving agent knows these
 *  envelopes are already drained and must not be re-fetched via `get_messages`. */
function pushBatchHeader(count: number): string {
  return count === 1
    ? "📨 mesh message (push-delivered, already drained — do not call get_messages for this; reply via agent_send echoing id as re):\n\n"
    : `📨 ${count} mesh messages (push-delivered, already drained — do not call get_messages for these; reply via agent_send echoing each id as re):\n\n`;
}

function pushDropNote(dropped: number): string {
  return dropped > 0
    ? `⚠ ${dropped} earlier local message(s) shed by the push queue bound (count/bytes)\n\n`
    : "";
}

/** Build a compact body-free pointer when one local envelope alone exceeds
 *  `maxBatchBytes` and has been moved to `inbox` for `get_messages` drain.
 *  `from` is JSON-quoted so untrusted wire text cannot smuggle formatting. */
export function oversizedPushNudgeContent(from: string): string {
  return (
    `📨 mesh message from ${JSON.stringify(from)} arrived (exceeds push byte cap) — ` +
    `call get_messages to read it and reply via agent_send (echo its id via re)`
  );
}

/** Wire hybrid push-turn delivery onto separate `pushQueue` and `inbox` queues:
 *  local peers push in rate-capped, byte-bounded, single-flight FIFO batches;
 *  cross-PC/`_relay` stay in `inbox`; transport failures fall back to `inbox`. */
export function createPushDeliveryCoordinator(
  options: PushDeliveryCoordinatorOptions,
): WakeCoordinator {
  const {
    inbox,
    pushQueue,
    gate,
    transport,
    scheduler,
    maxBatchBytes = PUSH_BATCH_MAX_BYTES,
    now = Date.now,
    onTransportError,
  } = options;

  let armed = false;
  let inFlight = false;
  let disposed = false;
  // Preserves shed-message counts across rejected deliveries so drop notices
  // are never lost on transient transport errors.
  let pendingDropped = 0;

  const armDeferred = (nowMs: number): void => {
    if (armed || disposed || pushQueue.length === 0) return;
    const delay = gate.retryAfterMs(nowMs);
    if (delay === null) return;
    armed = true;
    scheduler.arm(delay, () => {
      armed = false;
      if (disposed) return;
      tryFlush(true);
    });
  };

  const tryFlush = (isDeferred: boolean): void => {
    if (disposed || inFlight || pushQueue.length === 0) return;

    // Sample the clock ONCE across the rate-cap decision and deferred timer
    // arming so a tick crossing the cap boundary cannot strand queued work.
    const currentNow = now();
    const allowed = isDeferred
      ? gate.onDeferredRecheck(currentNow)
      : gate.onMessage(currentNow);
    if (!allowed) {
      armDeferred(currentNow);
      return;
    }

    // An immediate flush after the cap window elapsed supersedes any stale
    // deferred timer so it neither fires on an empty queue nor blocks re-arming.
    if (armed) {
      armed = false;
      scheduler.cancel();
    }

    const first = pushQueue.peek();
    if (!first) return;

    const dropped = pendingDropped + pushQueue.takeDropped();
    pendingDropped = 0;
    const dropNote = pushDropNote(dropped);
    const dropNoteBytes = Buffer.byteLength(dropNote, "utf8");
    const firstBlock = renderInboxMessage(first);
    const firstBlockBytes = Buffer.byteLength(firstBlock, "utf8");
    const singleHeaderBytes = Buffer.byteLength(pushBatchHeader(1), "utf8");

    let content: string;
    let rollbackBatch: WakeMessage[];

    if (singleHeaderBytes + dropNoteBytes + firstBlockBytes > maxBatchBytes) {
      // Oversized single local envelope: move to `inbox` before notifying so
      // even a transport failure cannot lose it, and push a compact pointer.
      pushQueue.shift();
      inbox.push(first);
      content = dropNote + oversizedPushNudgeContent(first.from);
      rollbackBatch = [];
    } else {
      pushQueue.shift();
      const batch: WakeMessage[] = [first];
      const blocks: string[] = [firstBlock];
      let blocksBytes = firstBlockBytes;

      while (pushQueue.length > 0) {
        const next = pushQueue.peek()!;
        const nextBlock = renderInboxMessage(next);
        const nextBlockBytes = Buffer.byteLength(nextBlock, "utf8");
        const nextHeaderBytes = Buffer.byteLength(pushBatchHeader(batch.length + 1), "utf8");
        const candidateBytes =
          nextHeaderBytes + dropNoteBytes + blocksBytes + BATCH_SEP_BYTES + nextBlockBytes;
        if (candidateBytes > maxBatchBytes) break;
        pushQueue.shift();
        batch.push(next);
        blocks.push(nextBlock);
        blocksBytes += BATCH_SEP_BYTES + nextBlockBytes;
      }

      content = pushBatchHeader(batch.length) + dropNote + blocks.join(BATCH_SEP);
      rollbackBatch = batch;
    }

    inFlight = true;
    let delivery: Promise<void>;
    try {
      delivery = Promise.resolve(transport.deliver(content));
    } catch (syncErr) {
      delivery = Promise.reject(syncErr);
    }

    void delivery.then(
      () => {
        inFlight = false;
        if (!disposed && pushQueue.length > 0) {
          tryFlush(true);
        }
      },
      (err: unknown) => {
        inFlight = false;
        pendingDropped += dropped;
        for (const msg of rollbackBatch) {
          inbox.push(msg);
        }
        try {
          onTransportError?.(err);
        } catch {
          /* diagnostic hook errors must not escape as unhandled rejections or strand subsequent flushes */
        }
        if (!disposed && pushQueue.length > 0) {
          tryFlush(true);
        }
      },
    );
  };

  return {
    onMessage(msg: WakeMessage): void {
      if (disposed) return;
      if (!isLocalPeerAddress(msg.from)) {
        // Cross-PC (`<pc>:`) and `_relay` stay buffered in `get_messages` only.
        inbox.push(msg);
        return;
      }
      pushQueue.push(msg);
      tryFlush(false);
    },
    onDrain(): void {
      // Draining `inbox` (`get_messages`) only clears cross-PC/`_relay`/fallback
      // traffic and MUST NOT cancel a pending deferred push for `pushQueue`.
    },
    dispose(): void {
      disposed = true;
      armed = false;
      scheduler.cancel();
    },
  };
}

// ── MCP server CLI/env options & mode-aware instructions ─────────────────────

/** Parsed startup options for `mesh_server.ts`. */
export interface MeshServerOptions {
  readonly cwd: string;
  readonly nameOverride: string | undefined;
  readonly bridgeEnabled: boolean;
  readonly pushDeliver: boolean;
}

/** Parse `mesh_server.ts` CLI flags and environment overrides.
 *  Push delivery defaults OFF and activates only on `--push-deliver` or
 *  `OUTPOST_PI_MCP_PUSH_DELIVER=1`. */
export function parseMeshServerOptions(
  argv: readonly string[],
  env: Readonly<Record<string, string | undefined>>,
  defaultCwd: string,
): MeshServerOptions {
  let cwd = env["OUTPOST_PI_MCP_CWD"] ?? defaultCwd;
  let nameOverride = env["OUTPOST_PI_MCP_NAME"];
  let bridgeEnabled = true;
  let pushDeliver = env[PUSH_DELIVER_ENV_VAR] === "1";

  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--cwd" && argv[i + 1]) {
      cwd = argv[++i]!;
    } else if (argv[i] === "--name" && argv[i + 1]) {
      nameOverride = argv[++i];
    } else if (argv[i] === "--no-bridge") {
      bridgeEnabled = false;
    } else if (argv[i] === PUSH_DELIVER_CLI_FLAG) {
      pushDeliver = true;
    }
  }

  return { cwd, nameOverride, bridgeEnabled, pushDeliver };
}

/** Build harness-agnostic MCP server instructions framed by delivery mode. */
export function buildMcpInstructions(agentName: string, pushDeliver: boolean): string {
  const deliveryGuidance = pushDeliver
    ? "Delivery mode: hybrid push-delivered. Local peer envelopes are push-delivered directly as turn input (already drained — do NOT call get_messages for them; reply via agent_send echoing each id as re). Cross-PC (`<pc>:`) and `_relay` messages (plus any local message that exceeded the push byte cap or fell back after a push transport failure) remain buffered in the inbox — call get_messages to read them."
    : "Delivery mode: inbox-drained. At the start of each turn call get_messages to check and clear incoming messages from other agents (when wake nudges are enabled, a body-free nudge may wake an idle session — still call get_messages to read the payload and id).";

  return [
    `You are connected to the outpost-pi agent mesh (requested name "${agentName}"; when the folder already hosts a same-named agent, your live name carries a #N coexistence suffix — confirm your exact address via list_peers).`,
    deliveryGuidance,
    "Use list_peers to discover available agents.",
    "Use agent_send to send messages — pass the exact address returned by list_peers (form `<cwd>@<name>`, `<pc>:` prefix cross-PC) VERBATIM; never build one by hand.",
    'Use "broadcast" as the target to send to all peers in your folder (cwd) at once.',
    "Follow the agent-network skill for full protocol details (delivery modes, ACK statuses, replies via UUID `re`, `<cwd>@<name>` addresses, cross-PC `<pc>:` prefix).",
  ].join("\n");
}

import { appendFile, chmod, mkdir, rename, stat, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

/** Content-free summary of relay frames dropped before bounded FIFO admission. */
export interface RelayDispatchOverflowAudit {
  queue: "data" | "control";
  droppedFrames: number;
  droppedBytes: number;
  maxPendingFrames: number;
  maxPendingBytes: number;
}

const DEFAULT_RELAY_DISPATCH_AUDIT_PATH = join(
  homedir(),
  ".pi",
  "remote",
  "relay-transport-audit.jsonl",
);
const RELAY_DISPATCH_AUDIT_MAX_BYTES = 256 * 1024;
const pendingAudits = new Map<RelayDispatchOverflowAudit["queue"], RelayDispatchOverflowAudit>();
let writeInFlight: Promise<void> | null = null;

/** Append one coalesced relay FIFO overflow summary to a bounded audit file. */
export function appendRelayDispatchOverflowAudit(event: RelayDispatchOverflowAudit): void {
  const pending = pendingAudits.get(event.queue);
  pendingAudits.set(event.queue, pending
    ? {
        queue: event.queue,
        droppedFrames: saturatingAdd(pending.droppedFrames, event.droppedFrames),
        droppedBytes: saturatingAdd(pending.droppedBytes, event.droppedBytes),
        maxPendingFrames: event.maxPendingFrames,
        maxPendingBytes: event.maxPendingBytes,
      }
    : { ...event });
  flushPendingAudit();
}

function flushPendingAudit(): void {
  if (writeInFlight || pendingAudits.size === 0) return;
  const events = [...pendingAudits.values()];
  pendingAudits.clear();
  const now = Date.now();
  const lines = events.map((event) => `${JSON.stringify({
    ts: now,
    reason: "dispatch_overflow",
    queue: event.queue,
    dropped_frames: event.droppedFrames,
    dropped_bytes: event.droppedBytes,
    max_pending_frames: event.maxPendingFrames,
    max_pending_bytes: event.maxPendingBytes,
  })}\n`).join("");
  writeInFlight = appendBounded(DEFAULT_RELAY_DISPATCH_AUDIT_PATH, lines)
    .catch(() => {
      // Audit is best-effort; dropping hostile ingress must not affect accepted traffic.
    })
    .finally(() => {
      writeInFlight = null;
      flushPendingAudit();
    });
}

function saturatingAdd(left: number, right: number): number {
  return Math.min(Number.MAX_SAFE_INTEGER, left + right);
}

async function appendBounded(path: string, line: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  let size = 0;
  try { size = (await stat(path)).size; } catch { /* new file */ }
  if (size + Buffer.byteLength(line, "utf8") > RELAY_DISPATCH_AUDIT_MAX_BYTES) {
    const rotatedPath = `${path}.1`;
    try { await unlink(rotatedPath); } catch { /* no predecessor */ }
    if (size <= RELAY_DISPATCH_AUDIT_MAX_BYTES) {
      try {
        await rename(path, rotatedPath);
        try { await chmod(rotatedPath, 0o600); } catch { /* unsupported permissions */ }
      } catch { /* no active file */ }
    } else {
      try { await unlink(path); } catch { /* no active file */ }
    }
  }
  await appendFile(path, line, { encoding: "utf8", mode: 0o600 });
  try { await chmod(path, 0o600); } catch { /* unsupported permissions */ }
}

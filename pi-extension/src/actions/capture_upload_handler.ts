import { createHash, randomUUID } from "node:crypto";
import { lstat, mkdir, realpath, readdir, rename, rm, writeFile } from "node:fs/promises";
import { relative, resolve } from "node:path";
import { TextDecoder } from "node:util";
import type { ClientMessage, ServerMessage } from "../protocol/types.js";
import {
  CAPTURE_UPLOAD_MAX_CHUNK_BYTES,
  CAPTURE_UPLOAD_MAX_EVENTS,
  CAPTURE_UPLOAD_MAX_TOTAL_BYTES,
  CAPTURE_UPLOAD_MIN_CHUNK_BYTES,
  CAPTURE_UPLOAD_RETENTION_MAX_FILES_PER_DAY,
  CAPTURE_UPLOAD_RETENTION_MAX_TOTAL_BYTES,
} from "../protocol/generated/protocol.generated.js";

export {
  CAPTURE_UPLOAD_MAX_CHUNK_BYTES,
  CAPTURE_UPLOAD_MAX_EVENTS,
  CAPTURE_UPLOAD_MAX_TOTAL_BYTES,
  CAPTURE_UPLOAD_MIN_CHUNK_BYTES,
  CAPTURE_UPLOAD_RETENTION_MAX_FILES_PER_DAY,
  CAPTURE_UPLOAD_RETENTION_MAX_TOTAL_BYTES,
};

const DEFAULT_STALE_AFTER_MS = 60_000;
const BASE64_RE = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
const CAPTURE_FILENAME_RE = /^app-capture-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z-[0-9a-f]{12}\.bin$/;
let captureCommitTail = Promise.resolve();

type CaptureBegin = Extract<ClientMessage, { type: "capture_upload_begin" }>;
type CaptureChunk = Extract<ClientMessage, { type: "capture_upload_chunk" }>;
type CaptureEnd = Extract<ClientMessage, { type: "capture_upload_end" }>;
type CaptureMessage = CaptureBegin | CaptureChunk | CaptureEnd;
type CaptureErrorCode = Extract<ServerMessage, { type: "capture_upload_error" }>["code"];

interface UploadState {
  readonly id: string;
  readonly deviceLabel: string;
  readonly totalBytes: number;
  readonly bytes: Buffer;
  readonly ownerId: string;
  readonly channel: CaptureReplySender;
  nextSequence: number;
  receivedBytes: number;
  touchedAt: number;
  finalizing: boolean;
}

interface CaptureCommitResult {
  readonly relativePath: string;
  readonly prunedFiles: number;
}

interface RetainedCapture {
  readonly path: string;
  readonly filename: string;
  readonly bytes: number;
  readonly day: string;
}

/** Minimal reply channel needed by the capture upload boundary. */
export interface CaptureReplySender {
  send(message: ServerMessage): void;
}

/** Effects supplied by the extension composition root. */
export interface CaptureUploadHandlerOptions {
  cwd(): string;
  note(message: string): void;
  now?: () => number;
  staleAfterMs?: number;
}

/**
 * Reassemble one bounded app debug capture and commit it atomically below the room cwd.
 *
 * The handler owns its stale-upload timer. Call `dispose` on extension teardown and
 * the matching detach method whenever an owner/channel ends so retained bytes cannot
 * outlive their channel or session boundary.
 */
export class CaptureUploadHandler {
  private active: UploadState | null = null;
  private readonly now: () => number;
  private readonly staleAfterMs: number;
  private readonly gcTimer: ReturnType<typeof setInterval>;
  private disposed = false;

  constructor(private readonly options: CaptureUploadHandlerOptions) {
    this.now = options.now ?? Date.now;
    this.staleAfterMs = options.staleAfterMs ?? DEFAULT_STALE_AFTER_MS;
    this.gcTimer = setInterval(() => this.gc(), Math.max(100, Math.floor(this.staleAfterMs / 2)));
    this.gcTimer.unref?.();
  }

  /** Route one generated capture-upload message and send exactly one typed reply. */
  async handle(ownerId: string, sender: CaptureReplySender, message: CaptureMessage): Promise<void> {
    switch (message.type) {
      case "capture_upload_begin":
        this.begin(ownerId, sender, message);
        return;
      case "capture_upload_chunk":
        this.chunk(ownerId, sender, message);
        return;
      case "capture_upload_end":
        await this.end(ownerId, sender, message);
        return;
    }
  }

  /** Drop retained bytes when the detached owner owns them. */
  detachOwner(ownerId: string): void {
    if (this.active?.ownerId === ownerId) this.active = null;
  }

  /** Drop retained bytes only when the lost owner channel owns them. */
  detachChannel(ownerId: string, channel: CaptureReplySender): void {
    if (this.active?.ownerId === ownerId && this.active.channel === channel) {
      this.active = null;
    }
  }

  /** Drop retained bytes for every owner during session teardown/replacement. */
  detachAll(): void {
    this.active = null;
  }

  /** Stop lifecycle-owned GC and release any abandoned capture. */
  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    clearInterval(this.gcTimer);
    this.active = null;
  }

  /** Test seam for deterministic timer/GC assertions. */
  gc(): void {
    if (this.active && this.now() - this.active.touchedAt >= this.staleAfterMs) {
      this.active = null;
    }
  }

  /** Test seam exposing whether bounded capture bytes are retained. */
  hasInflightUpload(): boolean {
    return this.active !== null;
  }

  private begin(ownerId: string, sender: CaptureReplySender, message: CaptureBegin): void {
    if (message.total_bytes <= 0 || message.total_bytes > CAPTURE_UPLOAD_MAX_TOTAL_BYTES) {
      this.fail(sender, message, "too_large", "Capture exceeds the 2 MiB delivery limit.");
      return;
    }
    if (this.disposed) {
      this.fail(sender, message, "not_found", "Capture upload runtime is no longer active.");
      return;
    }
    if (this.active !== null) {
      this.fail(sender, message, "busy", "Another capture upload is already in progress.");
      return;
    }
    this.active = {
      id: message.upload_id,
      deviceLabel: message.device_label,
      totalBytes: message.total_bytes,
      bytes: Buffer.alloc(message.total_bytes),
      ownerId,
      channel: sender,
      nextSequence: 0,
      receivedBytes: 0,
      touchedAt: this.now(),
      finalizing: false,
    };
    sender.send(this.reply(message, {
      type: "capture_upload_ack",
      in_reply_to: message.id,
      upload_id: message.upload_id,
      stage: "begin",
      next_sequence: 0,
    }));
  }

  private chunk(ownerId: string, sender: CaptureReplySender, message: CaptureChunk): void {
    const active = this.ownedActive(ownerId, sender, message.upload_id);
    if (!active) {
      this.fail(sender, message, "not_found", "Capture upload is not active.");
      return;
    }
    if (active.finalizing) {
      this.fail(sender, message, "busy", "Capture upload is being committed.");
      return;
    }
    if (message.sequence !== active.nextSequence) {
      this.abortWith(active, sender, message, "bad_sequence", "Capture chunks arrived out of sequence.");
      return;
    }
    const decodedLength = canonicalBase64DecodedLength(message.payload);
    if (!decodedLength || decodedLength > CAPTURE_UPLOAD_MAX_CHUNK_BYTES) {
      this.abortWith(active, sender, message, "too_large", "Capture chunk exceeds the 8 KiB limit.");
      return;
    }
    const offset = active.receivedBytes;
    if (
      decodedLength > active.totalBytes - offset ||
      decodedLength > CAPTURE_UPLOAD_MAX_TOTAL_BYTES - offset
    ) {
      this.abortWith(active, sender, message, "too_large", "Capture exceeds its declared size or the 2 MiB limit.");
      return;
    }
    const isFinalChunk = offset + decodedLength === active.totalBytes;
    if (!isFinalChunk && decodedLength < CAPTURE_UPLOAD_MIN_CHUNK_BYTES) {
      this.abortWith(
        active,
        sender,
        message,
        "too_large",
        "Capture chunks below 1 KiB are accepted only as the final chunk.",
      );
      return;
    }
    const written = active.bytes.write(message.payload, offset, decodedLength, "base64");
    if (written !== decodedLength) {
      this.abortWith(active, sender, message, "bad_sequence", "Capture chunk length was inconsistent.");
      return;
    }
    active.receivedBytes += decodedLength;
    active.nextSequence += 1;
    active.touchedAt = this.now();
    sender.send(this.reply(message, {
      type: "capture_upload_ack",
      in_reply_to: message.id,
      upload_id: message.upload_id,
      stage: "chunk",
      next_sequence: active.nextSequence,
      bytes: active.receivedBytes,
    }));
  }

  private async end(ownerId: string, sender: CaptureReplySender, message: CaptureEnd): Promise<void> {
    const active = this.ownedActive(ownerId, sender, message.upload_id);
    if (!active) {
      this.fail(sender, message, "not_found", "Capture upload is not active.");
      return;
    }
    if (active.finalizing) {
      this.fail(sender, message, "busy", "Capture upload is being committed.");
      return;
    }
    active.finalizing = true;
    try {
      if (active.receivedBytes !== active.totalBytes) {
        this.fail(sender, message, "bad_sequence", "Capture ended before all declared bytes arrived.");
        return;
      }
      const digest = createHash("sha256").update(active.bytes).digest("hex");
      if (digest !== message.sha256) {
        this.fail(sender, message, "checksum_mismatch", "Capture checksum did not match.");
        return;
      }
      const events = countCaptureEvents(active.bytes);
      if (events === null) {
        this.fail(sender, message, "invalid_capture", "Capture is not valid UTF-8 JSONL.");
        return;
      }

      let committed: CaptureCommitResult;
      try {
        committed = await this.commit(active.bytes, active.id);
      } catch {
        if (this.active === active && !this.disposed) {
          this.fail(sender, message, "io_error", "Capture could not be written in the room debug directory.");
        }
        return;
      }

      if (this.active !== active || this.disposed) return;
      const kb = Math.max(1, Math.ceil(active.bytes.length / 1024));
      const retentionNote = committed.prunedFiles > 0
        ? `; pruned ${committed.prunedFiles} older capture(s) to enforce retention`
        : "";
      this.options.note(
        `Debug capture delivered: ${committed.relativePath} (${events} events, ${kb} KB) from ${active.deviceLabel}${retentionNote}`,
      );
      sender.send(this.reply(message, {
        type: "capture_upload_ack",
        in_reply_to: message.id,
        upload_id: message.upload_id,
        stage: "delivered",
        path: committed.relativePath,
        bytes: active.bytes.length,
        events,
      }));
    } finally {
      if (this.active === active) this.active = null;
    }
  }

  protected commit(bytes: Buffer, uploadId: string): Promise<CaptureCommitResult> {
    return serializeCaptureCommit(async () => {
      const cwd = await realpath(this.options.cwd());
      const root = resolve(cwd, "debug");
      try {
        const entry = await lstat(root);
        if (entry.isSymbolicLink() || !entry.isDirectory()) {
          throw new Error("capture debug root is not a real directory");
        }
      } catch (error) {
        if (!isMissingPath(error)) throw error;
      }
      await mkdir(root, { recursive: true });
      const resolvedRoot = await realpath(root);
      assertContained(cwd, resolvedRoot);
      const iso = new Date(this.now()).toISOString().replaceAll(":", "-").replaceAll(".", "-");
      const idTail = createHash("sha256").update(uploadId).digest("hex").slice(-12);
      const filename = `app-capture-${iso}-${idTail}.bin`;
      const destination = resolve(resolvedRoot, filename);
      assertContained(resolvedRoot, destination);
      const temp = resolve(resolvedRoot, `.${filename}.${process.pid}.${randomUUID()}.tmp`);
      assertContained(resolvedRoot, temp);
      let landed = false;
      try {
        await writeFile(temp, bytes, { flag: "wx", mode: 0o600 });
        await rename(temp, destination);
        landed = true;
        const prunedFiles = await enforceCaptureRetention(resolvedRoot, destination);
        return { relativePath: `debug/${filename}`, prunedFiles };
      } catch (error) {
        await rm(temp, { force: true }).catch(() => undefined);
        if (landed) await rm(destination, { force: true }).catch(() => undefined);
        throw error;
      }
    });
  }

  private ownedActive(
    ownerId: string,
    channel: CaptureReplySender,
    uploadId: string,
  ): UploadState | null {
    const active = this.active;
    return active?.ownerId === ownerId && active.channel === channel && active.id === uploadId
      ? active
      : null;
  }

  private abortWith(
    active: UploadState,
    sender: CaptureReplySender,
    message: CaptureMessage,
    code: CaptureErrorCode,
    detail: string,
  ): void {
    if (this.active === active) this.active = null;
    this.fail(sender, message, code, detail);
  }

  private fail(
    sender: CaptureReplySender,
    message: CaptureMessage,
    code: CaptureErrorCode,
    detail: string,
  ): void {
    sender.send(this.reply(message, {
      type: "capture_upload_error",
      in_reply_to: message.id,
      upload_id: message.upload_id,
      code,
      message: detail,
    }));
  }

  private reply<T extends ServerMessage>(message: CaptureMessage, reply: T): T {
    return (message.session_id ? { ...reply, session_id: message.session_id } : reply) as T;
  }
}

function canonicalBase64DecodedLength(payload: string): number | null {
  if (!BASE64_RE.test(payload) || payload.length === 0) return null;
  const padding = payload.endsWith("==") ? 2 : payload.endsWith("=") ? 1 : 0;
  const finalDataChar = payload[payload.length - padding - 1];
  if (!finalDataChar) return null;
  const finalValue = base64Value(finalDataChar);
  if (finalValue < 0 || (padding === 2 && (finalValue & 0x0f) !== 0) || (padding === 1 && (finalValue & 0x03) !== 0)) {
    return null;
  }
  return (payload.length / 4) * 3 - padding;
}

function base64Value(char: string): number {
  const code = char.charCodeAt(0);
  if (code >= 65 && code <= 90) return code - 65;
  if (code >= 97 && code <= 122) return code - 71;
  if (code >= 48 && code <= 57) return code + 4;
  if (char === "+") return 62;
  if (char === "/") return 63;
  return -1;
}

function isMissingPath(error: unknown): boolean {
  return !!error && typeof error === "object" && "code" in error && error.code === "ENOENT";
}

function serializeCaptureCommit<T>(operation: () => Promise<T>): Promise<T> {
  const result = captureCommitTail.then(operation);
  captureCommitTail = result.then(() => undefined, () => undefined);
  return result;
}

async function enforceCaptureRetention(root: string, currentPath: string): Promise<number> {
  const captures: RetainedCapture[] = [];
  for (const entry of await readdir(root, { withFileTypes: true })) {
    if (!entry.isFile() || !CAPTURE_FILENAME_RE.test(entry.name)) continue;
    const path = resolve(root, entry.name);
    assertContained(root, path);
    let stats;
    try {
      stats = await lstat(path);
    } catch (error) {
      if (isMissingPath(error)) continue;
      throw error;
    }
    if (stats.isSymbolicLink() || !stats.isFile()) continue;
    captures.push({
      path,
      filename: entry.name,
      bytes: stats.size,
      day: entry.name.slice("app-capture-".length, "app-capture-".length + 10),
    });
  }

  captures.sort((a, b) => {
    if (a.path === currentPath) return 1;
    if (b.path === currentPath) return -1;
    return a.filename.localeCompare(b.filename);
  });
  const removals = new Set<string>();
  const byDay = new Map<string, RetainedCapture[]>();
  for (const capture of captures) {
    const sameDay = byDay.get(capture.day) ?? [];
    sameDay.push(capture);
    byDay.set(capture.day, sameDay);
  }
  for (const sameDay of byDay.values()) {
    while (sameDay.length > CAPTURE_UPLOAD_RETENTION_MAX_FILES_PER_DAY) {
      const oldest = sameDay.shift();
      if (oldest) removals.add(oldest.path);
    }
  }

  const retained = captures.filter((capture) => !removals.has(capture.path));
  let retainedBytes = retained.reduce((total, capture) => total + capture.bytes, 0);
  while (retainedBytes > CAPTURE_UPLOAD_RETENTION_MAX_TOTAL_BYTES && retained.length > 0) {
    const oldest = retained.shift();
    if (!oldest) break;
    removals.add(oldest.path);
    retainedBytes -= oldest.bytes;
  }

  for (const capture of captures) {
    if (removals.has(capture.path)) await rm(capture.path);
  }
  return removals.size;
}

function countCaptureEvents(bytes: Buffer): number | null {
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return null;
  }
  let events = 0;
  let start = 0;
  while (start <= text.length) {
    const newline = text.indexOf("\n", start);
    const end = newline === -1 ? text.length : newline;
    const lineEnd = end > start && text[end - 1] === "\r" ? end - 1 : end;
    if (lineEnd > start) {
      events += 1;
      if (events > CAPTURE_UPLOAD_MAX_EVENTS) return null;
      try {
        const value = JSON.parse(text.slice(start, lineEnd)) as unknown;
        if (!value || typeof value !== "object" || Array.isArray(value)) return null;
      } catch {
        return null;
      }
    }
    if (newline === -1) break;
    start = newline + 1;
  }
  return events > 0 ? events : null;
}

function assertContained(root: string, candidate: string): void {
  const rel = relative(root, candidate);
  if (rel === "" || rel.startsWith("..") || resolve(root, rel) !== candidate) {
    throw new Error("capture path escaped debug root");
  }
}

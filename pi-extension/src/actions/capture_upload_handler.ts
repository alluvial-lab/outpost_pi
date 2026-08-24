import { createHash, randomUUID } from "node:crypto";
import { mkdir, rename, rm, writeFile } from "node:fs/promises";
import { relative, resolve } from "node:path";
import { TextDecoder } from "node:util";
import type { ClientMessage, ServerMessage } from "../protocol/types.js";
import {
  CAPTURE_UPLOAD_MAX_CHUNK_BYTES,
  CAPTURE_UPLOAD_MAX_TOTAL_BYTES,
} from "../protocol/generated/protocol.generated.js";

export { CAPTURE_UPLOAD_MAX_CHUNK_BYTES, CAPTURE_UPLOAD_MAX_TOTAL_BYTES };

const DEFAULT_STALE_AFTER_MS = 60_000;
const BASE64_RE = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

type CaptureBegin = Extract<ClientMessage, { type: "capture_upload_begin" }>;
type CaptureChunk = Extract<ClientMessage, { type: "capture_upload_chunk" }>;
type CaptureEnd = Extract<ClientMessage, { type: "capture_upload_end" }>;
type CaptureMessage = CaptureBegin | CaptureChunk | CaptureEnd;
type CaptureErrorCode = Extract<ServerMessage, { type: "capture_upload_error" }>["code"];

interface UploadState {
  readonly id: string;
  readonly sessionId?: string;
  readonly deviceLabel: string;
  readonly totalBytes: number;
  readonly chunks: Buffer[];
  nextSequence: number;
  receivedBytes: number;
  touchedAt: number;
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
 * The handler owns its stale-upload timer. Call [dispose] on extension teardown and
 * [detach] whenever an owner channel detaches so retained capture bytes cannot outlive
 * their channel/session boundary.
 */
export class CaptureUploadHandler {
  private active: UploadState | null = null;
  private readonly now: () => number;
  private readonly staleAfterMs: number;
  private readonly gcTimer: ReturnType<typeof setInterval>;

  constructor(private readonly options: CaptureUploadHandlerOptions) {
    this.now = options.now ?? Date.now;
    this.staleAfterMs = options.staleAfterMs ?? DEFAULT_STALE_AFTER_MS;
    this.gcTimer = setInterval(() => this.gc(), Math.max(100, Math.floor(this.staleAfterMs / 2)));
    this.gcTimer.unref?.();
  }

  /** Route one generated capture-upload message and send exactly one typed reply. */
  async handle(sender: CaptureReplySender, message: CaptureMessage): Promise<void> {
    switch (message.type) {
      case "capture_upload_begin":
        this.begin(sender, message);
        return;
      case "capture_upload_chunk":
        this.chunk(sender, message);
        return;
      case "capture_upload_end":
        await this.end(sender, message);
        return;
    }
  }

  /** Drop retained bytes for a detached owner channel. */
  detach(): void {
    this.active = null;
  }

  /** Stop lifecycle-owned GC and release any abandoned capture. */
  dispose(): void {
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

  private begin(sender: CaptureReplySender, message: CaptureBegin): void {
    if (message.total_bytes <= 0 || message.total_bytes > CAPTURE_UPLOAD_MAX_TOTAL_BYTES) {
      this.fail(sender, message, "too_large", "Capture exceeds the 2 MiB delivery limit.");
      return;
    }
    if (this.active) {
      this.fail(sender, message, "busy", "Another capture upload is already in progress.");
      return;
    }
    this.active = {
      id: message.upload_id,
      sessionId: message.session_id,
      deviceLabel: message.device_label,
      totalBytes: message.total_bytes,
      chunks: [],
      nextSequence: 0,
      receivedBytes: 0,
      touchedAt: this.now(),
    };
    sender.send(this.reply(message, {
      type: "capture_upload_ack",
      in_reply_to: message.id,
      upload_id: message.upload_id,
      stage: "begin",
      next_sequence: 0,
    }));
  }

  private chunk(sender: CaptureReplySender, message: CaptureChunk): void {
    const active = this.active;
    if (!active || active.id !== message.upload_id) {
      this.fail(sender, message, "not_found", "Capture upload is not active.");
      return;
    }
    if (message.sequence !== active.nextSequence) {
      this.abortWith(sender, message, "bad_sequence", "Capture chunks arrived out of sequence.");
      return;
    }
    const decoded = decodeBase64(message.payload);
    if (!decoded || decoded.length === 0 || decoded.length > CAPTURE_UPLOAD_MAX_CHUNK_BYTES) {
      this.abortWith(sender, message, "too_large", "Capture chunk exceeds the 8 KiB limit.");
      return;
    }
    if (
      decoded.length > active.totalBytes - active.receivedBytes ||
      decoded.length > CAPTURE_UPLOAD_MAX_TOTAL_BYTES - active.receivedBytes
    ) {
      this.abortWith(sender, message, "too_large", "Capture exceeds its declared size or the 2 MiB limit.");
      return;
    }
    active.chunks.push(decoded);
    active.receivedBytes += decoded.length;
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

  private async end(sender: CaptureReplySender, message: CaptureEnd): Promise<void> {
    const active = this.active;
    if (!active || active.id !== message.upload_id) {
      this.fail(sender, message, "not_found", "Capture upload is not active.");
      return;
    }
    this.active = null;
    if (active.receivedBytes !== active.totalBytes) {
      this.fail(sender, message, "bad_sequence", "Capture ended before all declared bytes arrived.");
      return;
    }
    const bytes = Buffer.concat(active.chunks, active.receivedBytes);
    const digest = createHash("sha256").update(bytes).digest("hex");
    if (digest !== message.sha256) {
      this.fail(sender, message, "checksum_mismatch", "Capture checksum did not match.");
      return;
    }
    const events = countCaptureEvents(bytes);
    if (events === null) {
      this.fail(sender, message, "invalid_capture", "Capture is not valid UTF-8 JSONL.");
      return;
    }

    let relativePath: string;
    try {
      relativePath = await this.commit(bytes, active.id);
    } catch {
      this.fail(sender, message, "io_error", "Capture could not be written in the room debug directory.");
      return;
    }

    const kb = Math.max(1, Math.ceil(bytes.length / 1024));
    this.options.note(
      `Debug capture delivered: ${relativePath} (${events} events, ${kb} KB) from ${active.deviceLabel}`,
    );
    sender.send(this.reply(message, {
      type: "capture_upload_ack",
      in_reply_to: message.id,
      upload_id: message.upload_id,
      stage: "delivered",
      path: relativePath,
      bytes: bytes.length,
      events,
    }));
  }

  private async commit(bytes: Buffer, uploadId: string): Promise<string> {
    const root = resolve(this.options.cwd(), "debug");
    const iso = new Date(this.now()).toISOString().replaceAll(":", "-").replaceAll(".", "-");
    const idTail = createHash("sha256").update(uploadId).digest("hex").slice(-12);
    const filename = `app-capture-${iso}-${idTail}.bin`;
    const destination = resolve(root, filename);
    assertContained(root, destination);
    await mkdir(root, { recursive: true });
    const temp = resolve(root, `.${filename}.${process.pid}.${randomUUID()}.tmp`);
    assertContained(root, temp);
    try {
      await writeFile(temp, bytes, { flag: "wx", mode: 0o600 });
      await rename(temp, destination);
    } catch (error) {
      await rm(temp, { force: true }).catch(() => undefined);
      throw error;
    }
    return `debug/${filename}`;
  }

  private abortWith(
    sender: CaptureReplySender,
    message: CaptureMessage,
    code: CaptureErrorCode,
    detail: string,
  ): void {
    this.active = null;
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

function decodeBase64(payload: string): Buffer | null {
  if (!BASE64_RE.test(payload)) return null;
  const decoded = Buffer.from(payload, "base64");
  return decoded.toString("base64") === payload ? decoded : null;
}

function countCaptureEvents(bytes: Buffer): number | null {
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return null;
  }
  const lines = text.split(/\r?\n/).filter((line) => line.length > 0);
  if (lines.length === 0) return null;
  for (const line of lines) {
    try {
      const value = JSON.parse(line) as unknown;
      if (!value || typeof value !== "object" || Array.isArray(value)) return null;
    } catch {
      return null;
    }
  }
  return lines.length;
}

function assertContained(root: string, candidate: string): void {
  const rel = relative(root, candidate);
  if (rel === "" || rel.startsWith("..") || resolve(root, rel) !== candidate) {
    throw new Error("capture path escaped debug root");
  }
}

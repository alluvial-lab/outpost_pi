import { createHash } from "node:crypto";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import type { ClientMessage, ServerMessage } from "../protocol/types.js";
import {
  CAPTURE_UPLOAD_MAX_CHUNK_BYTES,
  CAPTURE_UPLOAD_MAX_TOTAL_BYTES,
  CaptureUploadHandler,
} from "./capture_upload_handler.js";

const roots: string[] = [];

afterEach(async () => {
  await Promise.all(roots.splice(0).map((root) => rm(root, { recursive: true, force: true })));
});

async function fixture(options: { now?: () => number; staleAfterMs?: number; cwd?: string } = {}) {
  const cwd = options.cwd ?? await mkdtemp(join(tmpdir(), "outpost-capture-upload-"));
  roots.push(cwd);
  const sent: ServerMessage[] = [];
  const notes: string[] = [];
  const handler = new CaptureUploadHandler({
    cwd: () => cwd,
    note: (message) => notes.push(message),
    now: options.now,
    staleAfterMs: options.staleAfterMs,
  });
  const sender = { send: (message: ServerMessage) => sent.push(message) };
  return { cwd, sent, notes, handler, sender };
}

function messages(bytes: Buffer, uploadId = "upload-safe-123") {
  const session_id = "session-1";
  const begin = {
    type: "capture_upload_begin",
    id: "begin-1",
    session_id,
    upload_id: uploadId,
    device_label: "Android device",
    total_bytes: bytes.length,
    capture_kind: "debug_log_jsonl",
  } as const;
  const chunks: Array<Extract<ClientMessage, { type: "capture_upload_chunk" }>> = [];
  for (let offset = 0, sequence = 0; offset < bytes.length; offset += CAPTURE_UPLOAD_MAX_CHUNK_BYTES, sequence++) {
    chunks.push({
      type: "capture_upload_chunk",
      id: `chunk-${sequence}`,
      session_id,
      upload_id: uploadId,
      sequence,
      payload: bytes.subarray(offset, offset + CAPTURE_UPLOAD_MAX_CHUNK_BYTES).toString("base64"),
    });
  }
  const end = {
    type: "capture_upload_end",
    id: "end-1",
    session_id,
    upload_id: uploadId,
    sha256: createHash("sha256").update(bytes).digest("hex"),
  } as const;
  return { begin, chunks, end };
}

async function deliver(
  handler: CaptureUploadHandler,
  sender: { send(message: ServerMessage): void },
  bytes: Buffer,
  uploadId?: string,
) {
  const wire = messages(bytes, uploadId);
  await handler.handle(sender, wire.begin);
  for (const chunk of wire.chunks) await handler.handle(sender, chunk);
  await handler.handle(sender, wire.end);
}

describe("CaptureUploadHandler", () => {
  test("reassembles, checksum-verifies, atomically writes, acknowledges, and notes once", async () => {
    const f = await fixture({ now: () => Date.parse("2026-08-24T12:34:56.789Z") });
    const bytes = Buffer.from('{"tag":"one"}\n{"tag":"two"}\n');
    await deliver(f.handler, f.sender, bytes);

    const delivered = f.sent.at(-1);
    expect(delivered).toMatchObject({
      type: "capture_upload_ack",
      stage: "delivered",
      bytes: bytes.length,
      events: 2,
      session_id: "session-1",
    });
    if (delivered?.type !== "capture_upload_ack" || !delivered.path) throw new Error("missing delivered path");
    expect(delivered.path).toMatch(/^debug\/app-capture-2026-08-24T12-34-56-789Z-[0-9a-f]{12}\.bin$/);
    expect(await readFile(join(f.cwd, delivered.path))).toEqual(bytes);
    expect((await readdir(join(f.cwd, "debug"))).every((name) => !name.endsWith(".tmp"))).toBe(true);
    expect(f.notes).toEqual([
      expect.stringMatching(/^Debug capture delivered: debug\/app-capture-.* \(2 events, 1 KB\) from Android device$/),
    ]);
    f.handler.dispose();
  });

  test("rejects declared and decoded oversize without retaining bytes", async () => {
    const f = await fixture();
    await f.handler.handle(f.sender, {
      type: "capture_upload_begin",
      id: "oversize",
      session_id: "session-1",
      upload_id: "large",
      device_label: "Android",
      total_bytes: CAPTURE_UPLOAD_MAX_TOTAL_BYTES + 1,
      capture_kind: "debug_log_jsonl",
    });
    expect(f.sent.at(-1)).toMatchObject({ type: "capture_upload_error", code: "too_large" });

    const declared = Buffer.alloc(CAPTURE_UPLOAD_MAX_CHUNK_BYTES + 1, 1);
    const wire = messages(declared);
    await f.handler.handle(f.sender, wire.begin);
    await f.handler.handle(f.sender, {
      ...wire.chunks[0]!,
      payload: declared.toString("base64"),
    });
    expect(f.sent.at(-1)).toMatchObject({ type: "capture_upload_error", code: "too_large" });
    expect(f.handler.hasInflightUpload()).toBe(false);
    f.handler.dispose();
  });

  test("strict sequence failure aborts the upload", async () => {
    const f = await fixture();
    const wire = messages(Buffer.from('{"tag":"one"}\n'));
    await f.handler.handle(f.sender, wire.begin);
    await f.handler.handle(f.sender, { ...wire.chunks[0]!, sequence: 1 });
    expect(f.sent.at(-1)).toMatchObject({ type: "capture_upload_error", code: "bad_sequence" });
    expect(f.handler.hasInflightUpload()).toBe(false);
    f.handler.dispose();
  });

  test("checksum mismatch produces a typed error and no file", async () => {
    const f = await fixture();
    const bytes = Buffer.from('{"tag":"one"}\n');
    const wire = messages(bytes);
    await f.handler.handle(f.sender, wire.begin);
    await f.handler.handle(f.sender, wire.chunks[0]!);
    await f.handler.handle(f.sender, { ...wire.end, sha256: "0".repeat(64) });
    expect(f.sent.at(-1)).toMatchObject({ type: "capture_upload_error", code: "checksum_mismatch" });
    await expect(readdir(join(f.cwd, "debug"))).rejects.toThrow();
    f.handler.dispose();
  });

  test("traversal-shaped upload ids cannot escape the room debug directory", async () => {
    const f = await fixture({ now: () => Date.parse("2026-08-24T00:00:00Z") });
    const bytes = Buffer.from('{"tag":"safe"}\n');
    await deliver(f.handler, f.sender, bytes, "../../outside/owned");
    const ack = f.sent.at(-1);
    expect(ack).toMatchObject({ type: "capture_upload_ack", stage: "delivered" });
    if (ack?.type !== "capture_upload_ack" || !ack.path) throw new Error("missing path");
    const landed = resolve(f.cwd, ack.path);
    expect(landed.startsWith(`${resolve(f.cwd, "debug")}/`)).toBe(true);
    expect(ack.path).not.toContain("..");
    f.handler.dispose();
  });

  test("timer GC and detach release an abandoned in-flight upload", async () => {
    let now = 1_000;
    const f = await fixture({ now: () => now, staleAfterMs: 500 });
    const wire = messages(Buffer.from('{"tag":"one"}\n'));
    await f.handler.handle(f.sender, wire.begin);
    expect(f.handler.hasInflightUpload()).toBe(true);
    now += 500;
    f.handler.gc();
    expect(f.handler.hasInflightUpload()).toBe(false);

    await f.handler.handle(f.sender, wire.begin);
    f.handler.detach();
    expect(f.handler.hasInflightUpload()).toBe(false);
    f.handler.dispose();
  });

  test("invalid JSONL is rejected before disk or session note", async () => {
    const f = await fixture();
    await deliver(f.handler, f.sender, Buffer.from("not-json\n"));
    expect(f.sent.at(-1)).toMatchObject({ type: "capture_upload_error", code: "invalid_capture" });
    expect(f.notes).toEqual([]);
    f.handler.dispose();
  });

  test("admits only one in-flight upload per session", async () => {
    const f = await fixture();
    const one = messages(Buffer.from('{"tag":"one"}\n'), "one");
    const two = messages(Buffer.from('{"tag":"two"}\n'), "two");
    await f.handler.handle(f.sender, one.begin);
    await f.handler.handle(f.sender, two.begin);
    expect(f.sent.at(-1)).toMatchObject({ type: "capture_upload_error", code: "busy" });
    expect(f.handler.hasInflightUpload()).toBe(true);
    f.handler.dispose();
  });
});

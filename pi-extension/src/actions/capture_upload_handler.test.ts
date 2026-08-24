import { createHash } from "node:crypto";
import { lstat, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import type { ClientMessage, ServerMessage } from "../protocol/types.js";
import {
  CAPTURE_UPLOAD_MAX_CHUNK_BYTES,
  CAPTURE_UPLOAD_MAX_EVENTS,
  CAPTURE_UPLOAD_MAX_TOTAL_BYTES,
  CAPTURE_UPLOAD_MIN_CHUNK_BYTES,
  CAPTURE_UPLOAD_RETENTION_MAX_FILES_PER_DAY,
  CAPTURE_UPLOAD_RETENTION_MAX_TOTAL_BYTES,
  CaptureUploadHandler,
} from "./capture_upload_handler.js";

const roots: string[] = [];
const OWNER_A = "owner-a";

class Deferred<T> {
  readonly promise: Promise<T>;
  resolve!: (value: T | PromiseLike<T>) => void;

  constructor() {
    this.promise = new Promise<T>((resolve) => { this.resolve = resolve; });
  }
}

class SlowCommitCaptureUploadHandler extends CaptureUploadHandler {
  readonly commitStarted = new Deferred<void>();
  readonly releaseCommit = new Deferred<void>();

  protected override async commit(bytes: Buffer, uploadId: string): Promise<string> {
    this.commitStarted.resolve(undefined);
    await this.releaseCommit.promise;
    return super.commit(bytes, uploadId);
  }
}

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
  await handler.handle(OWNER_A, sender, wire.begin);
  for (const chunk of wire.chunks) await handler.handle(OWNER_A, sender, chunk);
  await handler.handle(OWNER_A, sender, wire.end);
}

function jsonCaptureOfSize(bytes: number): Buffer {
  const prefix = '{"tag":"bulk","value":"';
  const suffix = '"}\n';
  return Buffer.from(`${prefix}${"x".repeat(bytes - Buffer.byteLength(prefix) - Buffer.byteLength(suffix))}${suffix}`);
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
    await f.handler.handle(OWNER_A, f.sender, {
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
    await f.handler.handle(OWNER_A, f.sender, wire.begin);
    await f.handler.handle(OWNER_A, f.sender, {
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
    await f.handler.handle(OWNER_A, f.sender, wire.begin);
    await f.handler.handle(OWNER_A, f.sender, { ...wire.chunks[0]!, sequence: 1 });
    expect(f.sent.at(-1)).toMatchObject({ type: "capture_upload_error", code: "bad_sequence" });
    expect(f.handler.hasInflightUpload()).toBe(false);
    f.handler.dispose();
  });

  test("checksum mismatch produces a typed error and no file", async () => {
    const f = await fixture();
    const bytes = Buffer.from('{"tag":"one"}\n');
    const wire = messages(bytes);
    await f.handler.handle(OWNER_A, f.sender, wire.begin);
    await f.handler.handle(OWNER_A, f.sender, wire.chunks[0]!);
    await f.handler.handle(OWNER_A, f.sender, { ...wire.end, sha256: "0".repeat(64) });
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

  test("rejects a symlinked debug root without writing through it", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "outpost-capture-symlink-cwd-"));
    const outside = await mkdtemp(join(tmpdir(), "outpost-capture-symlink-outside-"));
    roots.push(outside);
    await mkdir(outside, { recursive: true });
    await symlink(outside, join(cwd, "debug"), "dir");
    const f = await fixture({ cwd });

    await deliver(f.handler, f.sender, Buffer.from('{"tag":"blocked"}\n'));

    expect(f.sent.at(-1)).toMatchObject({ type: "capture_upload_error", code: "io_error" });
    expect(await readdir(outside)).toEqual([]);
    expect(f.notes).toEqual([]);
    f.handler.dispose();
  });

  test("holds admission until a slow async commit settles", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "outpost-capture-slow-commit-"));
    roots.push(cwd);
    const sent: ServerMessage[] = [];
    const sender = { send: (message: ServerMessage) => sent.push(message) };
    const handler = new SlowCommitCaptureUploadHandler({ cwd: () => cwd, note: () => undefined });
    const first = messages(Buffer.from('{"tag":"one"}\n'), "first");
    const second = messages(Buffer.from('{"tag":"two"}\n'), "second");
    await handler.handle(OWNER_A, sender, first.begin);
    await handler.handle(OWNER_A, sender, first.chunks[0]!);

    const finalizing = handler.handle(OWNER_A, sender, first.end);
    await handler.commitStarted.promise;
    await handler.handle(OWNER_A, sender, second.begin);

    expect(sent.at(-1)).toMatchObject({ type: "capture_upload_error", code: "busy" });
    expect(handler.hasInflightUpload()).toBe(true);
    handler.releaseCommit.resolve(undefined);
    await finalizing;
    expect(sent.at(-1)).toMatchObject({ type: "capture_upload_ack", stage: "delivered" });
    expect(handler.hasInflightUpload()).toBe(false);
    handler.dispose();
  });

  test("rejects undersized non-final chunks but accepts the exact floor plus a short final chunk", async () => {
    const f = await fixture();
    const bytes = Buffer.alloc(CAPTURE_UPLOAD_MIN_CHUNK_BYTES + 1, 0x20);
    const rejected = messages(bytes, "undersized-non-final");
    await f.handler.handle(OWNER_A, f.sender, rejected.begin);
    await f.handler.handle(OWNER_A, f.sender, {
      ...rejected.chunks[0]!,
      payload: bytes.subarray(0, CAPTURE_UPLOAD_MIN_CHUNK_BYTES - 1).toString("base64"),
    });
    expect(f.sent.at(-1)).toMatchObject({ type: "capture_upload_error", code: "too_large" });
    expect(f.handler.hasInflightUpload()).toBe(false);

    const validBytes = Buffer.from(`${" ".repeat(CAPTURE_UPLOAD_MIN_CHUNK_BYTES)}{}\n`);
    const valid = messages(validBytes, "minimum-plus-final");
    await f.handler.handle(OWNER_A, f.sender, valid.begin);
    await f.handler.handle(OWNER_A, f.sender, {
      ...valid.chunks[0]!,
      payload: validBytes.subarray(0, CAPTURE_UPLOAD_MIN_CHUNK_BYTES).toString("base64"),
    });
    await f.handler.handle(OWNER_A, f.sender, {
      ...valid.chunks[0]!,
      id: "chunk-final",
      sequence: 1,
      payload: validBytes.subarray(CAPTURE_UPLOAD_MIN_CHUNK_BYTES).toString("base64"),
    });
    await f.handler.handle(OWNER_A, f.sender, valid.end);
    expect(f.sent.at(-1)).toMatchObject({ type: "capture_upload_ack", stage: "delivered" });
    f.handler.dispose();
  });

  test("accepts the JSONL event ceiling and rejects the next event", async () => {
    const f = await fixture();
    const atLimit = Buffer.from('{"x":1}\n'.repeat(CAPTURE_UPLOAD_MAX_EVENTS));
    await deliver(f.handler, f.sender, atLimit, "events-at-limit");
    expect(f.sent.at(-1)).toMatchObject({
      type: "capture_upload_ack",
      stage: "delivered",
      events: CAPTURE_UPLOAD_MAX_EVENTS,
    });

    const overLimit = Buffer.from('{"x":1}\n'.repeat(CAPTURE_UPLOAD_MAX_EVENTS + 1));
    await deliver(f.handler, f.sender, overLimit, "events-over-limit");
    expect(f.sent.at(-1)).toMatchObject({ type: "capture_upload_error", code: "invalid_capture" });
    f.handler.dispose();
  });

  test("prunes oldest repeated uploads to the cumulative byte quota and reports pruning", async () => {
    let now = Date.parse("2026-08-24T00:00:00Z");
    const f = await fixture({ now: () => now });
    const bytes = jsonCaptureOfSize(CAPTURE_UPLOAD_MAX_TOTAL_BYTES);
    for (let index = 0; index < 5; index++) {
      await deliver(f.handler, f.sender, bytes, `byte-quota-${index}`);
      now += 1_000;
    }

    const names = (await readdir(join(f.cwd, "debug"))).filter((name) => name.startsWith("app-capture-"));
    const retainedBytes = (await Promise.all(names.map((name) => readFile(join(f.cwd, "debug", name)))))
      .reduce((total, capture) => total + capture.length, 0);
    expect(names).toHaveLength(4);
    expect(retainedBytes).toBeLessThanOrEqual(CAPTURE_UPLOAD_RETENTION_MAX_TOTAL_BYTES);
    expect(f.notes.at(-1)).toContain("pruned 1 older capture(s) to enforce retention");
    f.handler.dispose();
  });

  test("caps captures per day without pruning matching symlinks or directories", async () => {
    let now = Date.parse("2026-08-24T12:00:00Z");
    const f = await fixture({ now: () => now });
    const debug = join(f.cwd, "debug");
    await mkdir(debug);
    const target = join(f.cwd, "do-not-prune.txt");
    await writeFile(target, "safe");
    const symlinkName = "app-capture-2000-01-01T00-00-00-000Z-aaaaaaaaaaaa.bin";
    const directoryName = "app-capture-2000-01-01T00-00-00-000Z-bbbbbbbbbbbb.bin";
    await symlink(target, join(debug, symlinkName));
    await mkdir(join(debug, directoryName));

    for (let index = 0; index <= CAPTURE_UPLOAD_RETENTION_MAX_FILES_PER_DAY; index++) {
      await deliver(f.handler, f.sender, Buffer.from(`{"index":${index}}\n`), `daily-quota-${index}`);
      now += 1_000;
    }

    const entries = await readdir(debug, { withFileTypes: true });
    expect(entries.filter((entry) => entry.isFile() && entry.name.startsWith("app-capture-")))
      .toHaveLength(CAPTURE_UPLOAD_RETENTION_MAX_FILES_PER_DAY);
    expect((await lstat(join(debug, symlinkName))).isSymbolicLink()).toBe(true);
    expect((await lstat(join(debug, directoryName))).isDirectory()).toBe(true);
    expect(await readFile(target, "utf8")).toBe("safe");
    f.handler.dispose();
  });

  test("runtime disposal fences a finalization already waiting on disk commit", async () => {
    const cwd = await mkdtemp(join(tmpdir(), "outpost-capture-dispose-finalizing-"));
    roots.push(cwd);
    const sent: ServerMessage[] = [];
    const notes: string[] = [];
    const sender = { send: (message: ServerMessage) => sent.push(message) };
    const handler = new SlowCommitCaptureUploadHandler({
      cwd: () => cwd,
      note: (message) => notes.push(message),
    });
    const wire = messages(Buffer.from('{"tag":"shutdown"}\n'), "shutdown-finalizing");
    await handler.handle(OWNER_A, sender, wire.begin);
    await handler.handle(OWNER_A, sender, wire.chunks[0]!);

    const sentBeforeEnd = sent.length;
    const finalizing = handler.handle(OWNER_A, sender, wire.end);
    await handler.commitStarted.promise;
    handler.dispose();
    handler.releaseCommit.resolve(undefined);
    await finalizing;

    expect(sent).toHaveLength(sentBeforeEnd);
    expect(notes).toEqual([]);
    expect((await readdir(join(cwd, "debug"))).filter((name) => name.startsWith("app-capture-")))
      .toHaveLength(1);
  });

  test("clears only the owning owner/channel and clears every upload on transport loss", async () => {
    const f = await fixture();
    const otherSender = { send: (_message: ServerMessage) => undefined };
    const wire = messages(Buffer.from('{"tag":"one"}\n'));

    await f.handler.handle(OWNER_A, f.sender, wire.begin);
    f.handler.detachOwner("owner-b");
    f.handler.detachChannel(OWNER_A, otherSender);
    expect(f.handler.hasInflightUpload()).toBe(true);

    f.handler.detachChannel(OWNER_A, f.sender);
    expect(f.handler.hasInflightUpload()).toBe(false);
    await f.handler.handle(OWNER_A, f.sender, wire.begin);
    f.handler.detachOwner(OWNER_A);
    expect(f.handler.hasInflightUpload()).toBe(false);
    await f.handler.handle(OWNER_A, f.sender, wire.begin);
    f.handler.detachAll();
    expect(f.handler.hasInflightUpload()).toBe(false);
    f.handler.dispose();
  });

  test("timer GC and detach release an abandoned in-flight upload", async () => {
    let now = 1_000;
    const f = await fixture({ now: () => now, staleAfterMs: 500 });
    const wire = messages(Buffer.from('{"tag":"one"}\n'));
    await f.handler.handle(OWNER_A, f.sender, wire.begin);
    expect(f.handler.hasInflightUpload()).toBe(true);
    now += 500;
    f.handler.gc();
    expect(f.handler.hasInflightUpload()).toBe(false);

    await f.handler.handle(OWNER_A, f.sender, wire.begin);
    f.handler.detachAll();
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
    await f.handler.handle(OWNER_A, f.sender, one.begin);
    await f.handler.handle(OWNER_A, f.sender, two.begin);
    expect(f.sent.at(-1)).toMatchObject({ type: "capture_upload_error", code: "busy" });
    expect(f.handler.hasInflightUpload()).toBe(true);
    f.handler.dispose();
  });
});

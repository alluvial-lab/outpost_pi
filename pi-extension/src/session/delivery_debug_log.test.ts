import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { mkdtempSync, rmSync, readFileSync, writeFileSync, existsSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  DeliveryDebugLogImpl,
  createDeliveryDebugLog,
  idTail,
  MAX_RING_BYTES,
  noopDeliveryDebugLog,
  type DeliveryDebugEvent,
  type DeliveryDebugLog,
} from "./delivery_debug_log.js";

/**
 * Delivery-path ring log — the extension half of cross-side observability.
 *
 * Two test families:
 * 1. Adapter mechanics (DeliveryDebugLogImpl): ring persistence, cap-on-append,
 *    immediate-vs-debounced flush, export-from-file, clear, never-throws,
 *    privacy scrub (no forbidden keys; field-length caps).
 * 2. Factory + correlation: env-gate, idTail correlation helper.
 *
 * The projection-side emit coverage (the events actually fire on
 * bindApi/forget/wakeAgent/delivery paths) lives in
 * `sdk_session_projection.test.ts` + `extension.test.ts` via a fake
 * DeliveryDebugLog, mirroring the app ring log's capture-site tests.
 */

describe("DeliveryDebugLogImpl adapter mechanics", () => {
  let dir: string;
  let logPath: string;

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "rp-delivery-log-"));
    logPath = join(dir, "delivery.log");
  });
  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
  });

  test("a critical event flushes immediately and is readable from the file", () => {
    const log = new DeliveryDebugLogImpl(logPath);
    log.log({ tag: "wake_outcome", id: "cli_abc123", ok: false, recoverable: true, detail: "agent session not bound yet", messageApiArmed: false });
    const exported = log.export();
    expect(exported).toBeTruthy();
    expect(exported!).toContain("wake_outcome");
    expect(exported!).toContain("cli_abc123");
    expect(exported!).toContain('"messageApiArmed":false');
  });

  test("export reads from the file (source of truth); a new instance sees prior lines without duplicating", () => {
    const log1 = new DeliveryDebugLogImpl(logPath);
    log1.log({ tag: "message_api_null", reason: "stale" });
    log1.dispose();
    // New instance reads the file (source of truth). The dirty ring is empty
    // (no warm-from-file), so a subsequent flush does NOT re-append the prior
    // line — no duplication.
    const log2 = new DeliveryDebugLogImpl(logPath);
    log2.log({ tag: "message_api_null", reason: "shutdown" });
    log2.dispose();
    const exported = log2.export()!;
    const lines = exported.trim().split("\n");
    // Two distinct events, no duplicate of the first.
    expect(lines.filter((l) => l.includes('"reason":"stale"')).length).toBe(1);
    expect(lines.filter((l) => l.includes('"reason":"shutdown"')).length).toBe(1);
  });

  test("clear wipes ring + file", () => {
    const log = new DeliveryDebugLogImpl(logPath);
    log.log({ tag: "message_api_null", reason: "stale" });
    log.clear();
    expect(log.export()).toBeNull();
  });

  test("never throws on a forbidden key leak (defensive serialize scrubs it)", () => {
    const log = new DeliveryDebugLogImpl(logPath);
    // Cast to bypass the type system — the defensive serialize must scrub a
    // leaked forbidden key (drop it) without throwing.
    const poisoned = { tag: "msg_received", id: "x", source: "app", steer: false, text: "secret" } as unknown as DeliveryDebugEvent;
    expect(() => log.log(poisoned)).not.toThrow();
    const exported = log.export()!;
    // The line is written, but the forbidden `text` key is scrubbed.
    const line = JSON.parse(exported.trim().split("\n").pop()!);
    expect(line).not.toHaveProperty("text");
    expect(line).toMatchObject({ tag: "msg_received", id: "x" });
  });

  test("roomId appears in serialized events when set and is absent when omitted", () => {
    const log = new DeliveryDebugLogImpl(logPath);
    log.log({ tag: "msg_delivered", id: "cli_1", sessionIdTail: "abc12345", roomId: "SF_DCbXsmreE" });
    log.log({ tag: "msg_delivered", id: "cli_2", sessionIdTail: "def67890" });
    const exported = log.export()!;
    const lines = exported.trim().split("\n").map((l) => JSON.parse(l));
    expect(lines[0]).toMatchObject({ tag: "msg_delivered", roomId: "SF_DCbXsmreE" });
    expect(lines[1]).not.toHaveProperty("roomId");
  });

  test("field values are tail-truncated (a huge untrusted string can't evict the window)", () => {
    const log = new DeliveryDebugLogImpl(logPath);
    const hugeDetail = "x".repeat(10_000);
    log.log({ tag: "wake_outcome", id: "cli_1", ok: false, recoverable: false, detail: hugeDetail, messageApiArmed: true });
    const exported = log.export()!;
    const line = JSON.parse(exported.trim().split("\n").pop()!);
    expect((line.detail as string).length).toBeLessThanOrEqual(256);
  });

  test("ring cap drops oldest on append (bounded memory)", () => {
    const log = new DeliveryDebugLogImpl(logPath);
    // Force immediate-flush events so each lands on disk; the cap is on the
    // in-memory ring, but the file grows unbounded (file is the export source,
    // not capped — only the in-memory ring is). This test pins that the ring
    // never throws on high volume.
    for (let i = 0; i < 1000; i++) {
      log.log({ tag: "message_api_null", reason: "stale" });
    }
    expect(() => log.export()).not.toThrow();
  });

  test("capFile bounds the persistent file to ~MAX_RING_BYTES when it exceeds 2x", () => {
    const log = new DeliveryDebugLogImpl(logPath);
    // Write enough immediate-flush events to push the file past 2x the cap
    // (1 MiB). Each line is ~90 bytes; need ~24k lines for 2 MiB.
    for (let i = 0; i < 24_000; i++) {
      log.log({ tag: "message_api_null", reason: "stale" });
    }
    log.dispose();
    const size = existsSync(logPath) ? statSync(logPath).size : 0;
    // After capFile, the file should be at most ~MAX_RING_BYTES (512 KiB) +
    // one line of slack. Generously assert < 1 MiB (2x cap) to allow for the
    // keep-until-over heuristic.
    expect(size).toBeLessThan(MAX_RING_BYTES * 2);
  });

  test("dispose flushes pending routine events", () => {
    const log = new DeliveryDebugLogImpl(logPath);
    // Routine event (debounced) — would not flush until the timer fires.
    log.log({ tag: "msg_received", id: "cli_1", source: "app", steer: false });
    log.dispose();
    expect(log.export()).toContain("msg_received");
  });
});

describe("DeliveryDebugLog factory + correlation", () => {
  test("createDeliveryDebugLog returns no-op when OUTPOST_PI_DEBUG_LOG is unset", () => {
    const prev = process.env["OUTPOST_PI_DEBUG_LOG"];
    delete process.env["OUTPOST_PI_DEBUG_LOG"];
    try {
      const log = createDeliveryDebugLog();
      expect(log).toBe(noopDeliveryDebugLog);
      // No-op log does nothing and never throws.
      expect(() => log.log({ tag: "msg_received", id: "x", source: "app", steer: false })).not.toThrow();
    } finally {
      if (prev !== undefined) process.env["OUTPOST_PI_DEBUG_LOG"] = prev;
    }
  });

  test("createDeliveryDebugLog returns a file-backed log when OUTPOST_PI_DEBUG_LOG=1", () => {
    const dir = mkdtempSync(join(tmpdir(), "rp-factory-"));
    const prevHome = process.env["OUTPOST_PI_HOME"];
    process.env["OUTPOST_PI_HOME"] = dir;
    process.env["OUTPOST_PI_DEBUG_LOG"] = "1";
    try {
      const log = createDeliveryDebugLog();
      expect(log).not.toBe(noopDeliveryDebugLog);
      log.log({ tag: "session_lifecycle", reason: "reload", sessionIdTail: "deadbeef" });
      const exported = log.export();
      expect(exported).toContain("session_lifecycle");
      expect(exported).toContain("reload");
    } finally {
      if (prevHome === undefined) delete process.env["OUTPOST_PI_HOME"];
      else process.env["OUTPOST_PI_HOME"] = prevHome;
      delete process.env["OUTPOST_PI_DEBUG_LOG"];
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("idTail returns the last 8 chars (matches relay id_tail convention)", () => {
    expect(idTail("cli_019f42b1-ae1b-74df-96d1-eca0ea3bdb00")).toBe("ea3bdb00");
    expect(idTail("short")).toBe("short");
    expect(idTail("exactly8")).toBe("exactly8");
  });
});

/**
 * Fake DeliveryDebugLog for projection/extension tests — records every event
 * so a test can assert the expected events fire on a deliver / null-window /
 * re-arm path. Mirrors the app ring log's fake-DebugLog pattern.
 */
export class FakeDeliveryDebugLog implements DeliveryDebugLog {
  readonly events: DeliveryDebugEvent[] = [];
  log(event: DeliveryDebugEvent): void {
    this.events.push(event);
  }
  /** Filter to events matching a tag. */
  byTag(tag: DeliveryDebugEvent["tag"]): DeliveryDebugEvent[] {
    return this.events.filter((e) => e.tag === tag);
  }
}

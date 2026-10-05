import { describe, expect, test } from "vitest";
import { BoundedInbox, INBOX_LIMITS, jsonByteSize, renderInboxMessage } from "./inbox.js";

interface Msg { from: string; body: string }

const sizeOf = (m: Msg) => JSON.stringify(m).length;

describe("BoundedInbox (gate-security-mcp-inbox-unbounded)", () => {
  test("retains within both limits and drains everything with drop count 0", () => {
    const inbox = new BoundedInbox<Msg>(sizeOf, { maxMessages: 3, maxBytes: 10_000 });
    inbox.push({ from: "a", body: "1" });
    inbox.push({ from: "b", body: "2" });
    const { items, dropped } = inbox.drain();
    expect(items.map((m) => m.from)).toEqual(["a", "b"]);
    expect(dropped).toBe(0);
    expect(inbox.length).toBe(0);
  });

  test("count overflow sheds the OLDEST message, keeps the newest", () => {
    const inbox = new BoundedInbox<Msg>(sizeOf, { maxMessages: 2, maxBytes: 10_000 });
    inbox.push({ from: "a", body: "1" });
    inbox.push({ from: "b", body: "2" });
    inbox.push({ from: "c", body: "3" });
    const { items, dropped } = inbox.drain();
    expect(items.map((m) => m.from)).toEqual(["b", "c"]); // a was shed
    expect(dropped).toBe(1);
  });

  test("byte overflow sheds oldest until under budget; drop count surfaces", () => {
    const budget = sizeOf({ from: "x", body: "" }) * 3;
    const inbox = new BoundedInbox<Msg>(sizeOf, { maxMessages: 100, maxBytes: budget });
    for (let i = 0; i < 10; i++) inbox.push({ from: `p${i}`, body: "" });
    const { items, dropped } = inbox.drain();
    // The retained set must actually be UNDER the byte budget — a loose
    // length bound would miss precisely the resource violation this gate
    // exists to catch (e.g. 3 × 23B = 69 > a 66B budget).
    const retainedBytes = items.reduce((n, m) => n + sizeOf(m), 0);
    expect(retainedBytes).toBeLessThanOrEqual(budget);
    expect(items.map((m) => m.from)).toEqual(["p8", "p9"]);
    expect(dropped).toBe(8);
  });

  test("a single message larger than the byte budget is rejected, not retained", () => {
    const inbox = new BoundedInbox<Msg>(sizeOf, { maxMessages: 10, maxBytes: 16 });
    inbox.push({ from: "huge", body: "x".repeat(200) });
    expect(inbox.length).toBe(0);
    const { items, dropped } = inbox.drain();
    expect(items).toEqual([]);
    expect(dropped).toBe(1);
  });

  test("find/some read retained state for wake-edge decisions", () => {
    const inbox = new BoundedInbox<Msg>(sizeOf, { maxMessages: 10, maxBytes: 10_000 });
    inbox.push({ from: "remote:/x@y", body: "" });
    expect(inbox.some((m) => m.from.startsWith("/"))).toBe(false); // remote only: no local edge
    inbox.push({ from: "/local@z", body: "" });
    expect(inbox.some((m) => m.from.startsWith("/"))).toBe(true);
    expect(inbox.find((m) => m.from.startsWith("/"))!.from).toBe("/local@z");
  });

  test("drain resets the drop counter", () => {
    const inbox = new BoundedInbox<Msg>(sizeOf, { maxMessages: 1, maxBytes: 10_000 });
    inbox.push({ from: "a", body: "1" });
    inbox.push({ from: "b", body: "2" });
    expect(inbox.drain().dropped).toBe(1);
    inbox.push({ from: "c", body: "3" });
    expect(inbox.drain().dropped).toBe(0);
  });

  test("default limits match the documented security contract", () => {
    expect(INBOX_LIMITS.maxMessages).toBe(1_000);
    expect(INBOX_LIMITS.maxBytes).toBe(4 * 1024 * 1024);
  });
});

describe("byte accounting (final-review regression)", () => {
  test("jsonByteSize counts UTF-8 bytes, not UTF-16 code units", () => {
    const s = "é".repeat(1_000); // 1 BMP char = 1 code unit, 2 UTF-8 bytes
    expect(s.length).toBe(1_000);
    // JSON serialization quotes the string: 2,000 payload bytes + 2 quotes.
    expect(jsonByteSize(s)).toBe(2_002);
  });

  test("a multi-byte message beyond the byte budget is rejected even when its code-unit length fits", () => {
    // Reproduces the reviewer's shape at miniature scale: unit-based
    // accounting admitted ~1.5x the ceiling; byte-based must not.
    const inbox = new BoundedInbox<Msg>(jsonByteSize, { maxMessages: 10, maxBytes: 200 });
    const body = "é".repeat(120); // ~124 units (fits 200), ~248 bytes (exceeds)
    inbox.push({ from: "a", body });
    expect(inbox.length).toBe(0);
    expect(inbox.drain().dropped).toBe(1);
  });
});

describe("drain rendering (final-review regression)", () => {
  const deepBody = (depth: number): unknown => {
    let v: unknown = "leaf";
    for (let i = 0; i < depth; i++) v = [v];
    return v;
  };

  test("deep JSON renders compact — output linear in retained bytes, never pretty", () => {
    const body = deepBody(2_000);
    const rendered = renderInboxMessage({ from: "/a@b", id: "i", re: null, at: "t", body });
    const compact = JSON.stringify(body);
    // No indentation amplification: rendered size ≈ compact body + a bounded
    // envelope (~100 chars). Pretty-printing this body produces GBs.
    expect(rendered.length).toBeLessThanOrEqual(compact.length + 120);
    expect(rendered).not.toContain("\n  "); // no indented lines anywhere
  });

  test("drain response stays linear across many messages", () => {
    const inbox = new BoundedInbox<Msg>(jsonByteSize, { maxMessages: 1_000, maxBytes: 4 * 1024 * 1024 });
    for (let i = 0; i < 300; i++) inbox.push({ from: "p", body: deepBody(40) });
    const { items } = inbox.drain();
    const rendered = items.map((m) => renderInboxMessage({ ...m, id: "i", re: null, at: "t" })).join("\n\n");
    const compactTotal = items.reduce((n, m) => n + jsonByteSize(m), 0);
    expect(rendered.length).toBeLessThan(compactTotal + items.length * 120 + 1);
  });
});

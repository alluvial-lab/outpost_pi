import { describe, expect, test } from "vitest";
import { BoundedInbox, INBOX_LIMITS } from "./inbox.js";

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
    const inbox = new BoundedInbox<Msg>(sizeOf, { maxMessages: 100, maxBytes: sizeOf({ from: "x", body: "" }) * 3 });
    for (let i = 0; i < 10; i++) inbox.push({ from: `p${i}`, body: "" });
    const { items, dropped } = inbox.drain();
    expect(items.length).toBeLessThanOrEqual(3);
    expect(dropped).toBe(10 - items.length);
    expect(items[items.length - 1]!.from).toBe("p9"); // newest always retained
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

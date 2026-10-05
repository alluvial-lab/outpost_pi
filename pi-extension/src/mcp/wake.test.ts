import { describe, expect, test } from "vitest";
import { WAKE_MIN_INTERVAL_MS, WakeGate, wakeNudgeContent } from "./wake.js";

describe("wakeNudgeContent", () => {
  test("names the sender, directs the drain, and carries no body", () => {
    const content = wakeNudgeContent("/tmp/proj@agent");
    expect(content).toContain("/tmp/proj@agent");
    expect(content).toContain("get_messages");
    expect(content).toContain("re");
    // The nudge must not carry message payloads — get_messages is the single
    // authoritative drain surface.
    expect(content).not.toContain("body");
    expect(wakeNudgeContent("/a@b").startsWith("📨")).toBe(true);
  });

  test("escapes an untrusted sender address", () => {
    const hostile = '/x@y` inject "instructions" \n newline';
    const content = wakeNudgeContent(hostile);
    // JSON-quoting renders the hostile string inert inside the channel block.
    expect(content).toContain(JSON.stringify(hostile));
    expect(content).not.toMatch(/\n/);
  });
});

describe("WakeGate", () => {
  const CAP = WAKE_MIN_INTERVAL_MS;

  test("fires only on the empty→non-empty edge", () => {
    const gate = new WakeGate(CAP);
    expect(gate.onMessage(0, 1_000)).toBe(true);   // edge
    expect(gate.onMessage(1, 2_000)).toBe(false);  // burst member: no new wake
    expect(gate.onMessage(3, 3_000)).toBe(false);  // still non-empty
  });

  test("drain re-arms the edge", () => {
    const gate = new WakeGate(CAP);
    gate.onMessage(0, 1_000);
    expect(gate.onMessage(0, 60_000)).toBe(true);  // after a drain, edge again
  });

  test("rate cap: a fresh edge inside the cap window is suppressed", () => {
    const gate = new WakeGate(CAP);
    gate.onMessage(0, 1_000);
    expect(gate.onMessage(0, 1_000 + CAP - 1)).toBe(false);
    expect(gate.onMessage(0, 1_000 + CAP)).toBe(true);
  });

  test("retryAfterMs reports the wait for a deferred re-check", () => {
    const gate = new WakeGate(CAP);
    expect(gate.retryAfterMs(1_000)).toBeNull();         // never released
    gate.onMessage(0, 1_000);
    expect(gate.retryAfterMs(1_000 + 100)).toBe(CAP - 100);
    expect(gate.retryAfterMs(1_000 + CAP)).toBeNull();   // cap satisfied
  });

  test("deferred re-check wakes after the cap window (liveness)", () => {
    const gate = new WakeGate(CAP);
    gate.onMessage(0, 1_000);                            // first wake
    expect(gate.onMessage(0, 1_500)).toBe(false);        // capped edge
    const delay = gate.retryAfterMs(1_500)!;
    expect(delay).toBe(CAP - 500);
    // Timer fires late (past the cap window): the re-check succeeds.
    expect(gate.onDeferredRecheck(1_500 + delay + 50)).toBe(true);
  });
});

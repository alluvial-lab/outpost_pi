import { describe, expect, test } from "vitest";
import {
  WAKE_MIN_INTERVAL_MS,
  WakeGate,
  createWakeCoordinator,
  isLocalPeerAddress,
  wakeNudgeContent,
  type WakeMessage,
  type WakeScheduler,
} from "./wake.js";
import { BoundedInbox } from "./inbox.js";

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

  test("a re-check that fires inside the cap window is re-suppressed (skew safety)", () => {
    const gate = new WakeGate(CAP);
    gate.onMessage(0, 1_000);
    gate.onMessage(0, 1_500);                            // suppressed edge
    // Timer fires EARLY (clock skew): the re-check must fail, not force a wake —
    // the wiring re-arms instead of dropping the pending work.
    expect(gate.onDeferredRecheck(1_800)).toBe(false);
    expect(gate.retryAfterMs(1_800)).toBe(CAP - 800);
  });
});

describe("isLocalPeerAddress", () => {
  test("bare cwd addresses are local; pc:-prefixed are remote", () => {
    expect(isLocalPeerAddress("/home/a/proj@agent")).toBe(true);
    expect(isLocalPeerAddress("laptop:/home/a/proj@agent")).toBe(false);
    expect(isLocalPeerAddress("pc-two:/tmp/x@y")).toBe(false);
  });
});

// ── Coordinator wiring tests (gate-tests findings: the server-boundary
// behavior was previously only reachable through the unimportable script) ──

class FakeScheduler implements WakeScheduler {
  armed: { delayMs: number; fire: () => void } | null = null;
  cancelled = 0;
  arm(delayMs: number, fire: () => void): void { this.armed = { delayMs, fire }; }
  cancel(): void { this.cancelled++; this.armed = null; }
}

function msg(from: string, body: unknown = "x", id = "id-1"): WakeMessage {
  return { from, body, id, re: null, at: "t" };
}

function rig(limits = { maxMessages: 100, maxBytes: 1_000_000 }) {
  const inbox = new BoundedInbox<WakeMessage>((m) => JSON.stringify(m).length, limits);
  const gate = new WakeGate(WAKE_MIN_INTERVAL_MS);
  const emits: string[] = [];
  const scheduler = new FakeScheduler();
  let clock = 10_000;
  const coord = createWakeCoordinator(
    inbox, gate, (from) => emits.push(from), scheduler, () => clock,
  );
  return { inbox, coord, emits, scheduler, tick: (ms: number) => { clock += ms; } };
}

describe("createWakeCoordinator (server-boundary wiring)", () => {
  test("remote-only traffic never wakes; messages stay drainable", () => {
    const r = rig();
    r.coord.onMessage(msg("laptop:/x@y", { secret: "BODY-ID-SENTINEL" }));
    r.coord.onMessage(msg("pc2:/y@z"));
    expect(r.emits).toEqual([]);
    expect(r.scheduler.armed).toBeNull();
    const { items } = r.inbox.drain();
    expect(items.map((m) => m.from)).toEqual(["laptop:/x@y", "pc2:/y@z"]);
  });

  test("a local message behind an undrained remote one still wakes, once, naming the local sender", () => {
    const r = rig();
    r.coord.onMessage(msg("laptop:/x@y"));
    r.coord.onMessage(msg("/local@a", "SENTINEL-BODY", "SENTINEL-ID"));
    expect(r.emits).toEqual(["/local@a"]); // local sender, not the remote
    // Content exclusion composes with wakeNudgeContent (which carries no
    // body/id) — the coordinator hands the adapter only the `from` string.
    const content = wakeNudgeContent(r.emits[0]!);
    expect(content).not.toContain("SENTINEL");
    // A second local while the first is undrained: no new edge, no emit.
    r.coord.onMessage(msg("/local@b"));
    expect(r.emits).toEqual(["/local@a"]);
  });

  test("burst of simultaneous local messages wakes exactly once", () => {
    const r = rig();
    r.coord.onMessage(msg("/a@1"));
    r.coord.onMessage(msg("/a@2"));
    r.coord.onMessage(msg("/a@3"));
    expect(r.emits).toEqual(["/a@1"]);
  });

  test("cap-suppressed edge arms a deferred re-check that fires without a new arrival (liveness)", () => {
    const r = rig();
    r.coord.onMessage(msg("/a@1")); // wake (t=10000)
    r.inbox.drain(); // the woken session read the message
    r.coord.onDrain();
    r.tick(WAKE_MIN_INTERVAL_MS - 1_000);
    r.coord.onMessage(msg("/a@2")); // fresh edge, capped → armed
    expect(r.emits).toEqual(["/a@1"]);
    expect(r.scheduler.armed).not.toBeNull();
    r.tick(5_000); // past the cap window
    r.scheduler.armed!.fire();
    expect(r.emits).toEqual(["/a@1", "/a@2"]);
    // /a@1 was drained mid-test; /a@2 (the capped message the deferred
    // re-check surfaced) is still retained.
    expect(r.inbox.drain().items.map((m) => m.from)).toEqual(["/a@2"]);
  });

  test("drain before the deferred fire cancels it — no phantom wake", () => {
    const r = rig();
    r.coord.onMessage(msg("/a@1"));
    r.tick(WAKE_MIN_INTERVAL_MS - 1_000);
    r.coord.onMessage(msg("/a@2")); // capped, armed
    r.inbox.drain();
    r.coord.onDrain();
    expect(r.scheduler.cancelled).toBe(1);
    expect(r.scheduler.armed).toBeNull();
    // Even if a stale fire somehow ran, the inbox holds no local message.
    r.tick(WAKE_MIN_INTERVAL_MS);
    // (no scheduler.armed to fire — cancelled)
    expect(r.emits).toEqual(["/a@1"]);
  });

  test("early fire inside the cap window re-arms instead of forcing or dropping", () => {
    const r = rig();
    r.coord.onMessage(msg("/a@1"));
    r.inbox.drain();
    r.coord.onDrain();
    r.tick(1_000);
    r.coord.onMessage(msg("/a@2")); // fresh edge, capped, armed (~4s remaining)
    r.tick(1_000); // still inside the cap window
    r.scheduler.armed!.fire(); // fires early (skew)
    expect(r.emits).toEqual(["/a@1"]); // no forced wake
    expect(r.scheduler.armed).not.toBeNull(); // re-armed
    r.tick(WAKE_MIN_INTERVAL_MS); // now past the window
    r.scheduler.armed!.fire();
    expect(r.emits).toEqual(["/a@1", "/a@2"]);
  });

  test("eviction of all capped locals before the deferred fire: no wake, drops surfaced, later local still wakes", () => {
    const r = rig({ maxMessages: 4, maxBytes: 1_000_000 });
    r.coord.onMessage(msg("/a@1")); // wake
    r.inbox.drain(); // the woken session read the message — the edge re-arms
    r.coord.onDrain();
    r.tick(1_000);
    r.coord.onMessage(msg("/a@2")); // fresh edge, capped → armed
    // Remote flood evicts both retained locals (drop-oldest, count budget 4).
    r.coord.onMessage(msg("pc:/r@1"));
    r.coord.onMessage(msg("pc:/r@2"));
    r.coord.onMessage(msg("pc:/r@3"));
    r.coord.onMessage(msg("pc:/r@4"));
    r.tick(WAKE_MIN_INTERVAL_MS);
    r.scheduler.armed!.fire();
    // The deferred re-check finds no local message: no remote-triggered wake.
    expect(r.emits).toEqual(["/a@1"]);
    const { items, dropped } = r.inbox.drain();
    expect(items.every((m) => m.from.startsWith("pc:"))).toBe(true);
    expect(dropped).toBe(1); // /a@2 shed by the flood (/a@1 was drained)
    // A fresh local message is a genuine new edge and wakes again.
    r.coord.onMessage(msg("/a@3"));
    expect(r.emits).toEqual(["/a@1", "/a@3"]);
  });
});

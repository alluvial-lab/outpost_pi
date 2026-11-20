import { describe, expect, test } from "vitest";
import { Buffer } from "node:buffer";
import {
  WAKE_MIN_INTERVAL_MS,
  WakeGate,
  createWakeCoordinator,
  isLocalPeerAddress,
  wakeNudgeContent,
  type WakeMessage,
  type WakeScheduler,
} from "./wake.js";
import {
  PUSH_BATCH_MAX_BYTES,
  buildMcpInstructions,
  createPushDeliveryCoordinator,
  oversizedPushNudgeContent,
  parseMeshServerOptions,
  type PushDeliveryTransport,
} from "./push_delivery.js";
import { BoundedInbox, jsonByteSize } from "./inbox.js";

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

describe("WakeGate (rate cap only — edge semantics live in the coordinator)", () => {
  const CAP = WAKE_MIN_INTERVAL_MS;

  test("first eligible wake releases; an immediate second is capped", () => {
    const gate = new WakeGate(CAP);
    expect(gate.onMessage(1_000)).toBe(true);
    expect(gate.onMessage(1_000 + CAP - 1)).toBe(false);
    expect(gate.onMessage(1_000 + CAP)).toBe(true);
  });

  test("retryAfterMs reports the wait for a deferred re-check", () => {
    const gate = new WakeGate(CAP);
    expect(gate.retryAfterMs(1_000)).toBeNull();         // never released
    gate.onMessage(1_000);
    expect(gate.retryAfterMs(1_000 + 100)).toBe(CAP - 100);
    expect(gate.retryAfterMs(1_000 + CAP)).toBeNull();   // cap satisfied
  });

  test("deferred re-check wakes after the cap window (liveness)", () => {
    const gate = new WakeGate(CAP);
    gate.onMessage(1_000);                            // first wake
    expect(gate.onMessage(1_500)).toBe(false);        // capped edge
    const delay = gate.retryAfterMs(1_500)!;
    expect(delay).toBe(CAP - 500);
    // Timer fires late (past the cap window): the re-check succeeds.
    expect(gate.onDeferredRecheck(1_500 + delay + 50)).toBe(true);
  });

  test("a re-check that fires inside the cap window is re-suppressed (skew safety)", () => {
    const gate = new WakeGate(CAP);
    gate.onMessage(1_000);
    gate.onMessage(1_500);                            // suppressed edge
    // Timer fires EARLY (clock skew): the re-check must fail, not force a wake —
    // the coordinator re-arms instead of dropping the pending work.
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

  test("[security regression] slash-leading base64 fallback PC labels are remote", () => {
    // Unnamed-PC labels are raw base64 pubkey prefixes (siblings.ts) and
    // base64 permits a leading '/' — the startsWith('/') heuristic would
    // have classified this local and woken the session.
    expect(isLocalPeerAddress("/wAAAAAA:/tmp/remote@peer")).toBe(false);
    expect(isLocalPeerAddress("/9+/AbCd:/x@y")).toBe(false);
  });

  test("relay system envelopes are never wake-eligible", () => {
    expect(isLocalPeerAddress("_relay")).toBe(false);
  });

  test("fail-closed: a local name containing a colon parses as prefixed (no wake)", () => {
    // Documented availability edge — buffered, never a security loss.
    expect(isLocalPeerAddress("weird:name@local")).toBe(false);
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

  test("dispose cancels pending deferred wake and suppresses late arrivals", () => {
    const r = rig();
    r.coord.onMessage(msg("/a@1"));
    r.inbox.drain();
    r.coord.onDrain();
    r.tick(1_000);
    r.coord.onMessage(msg("/a@2")); // capped, armed
    expect(r.scheduler.armed).not.toBeNull();
    r.coord.dispose();
    expect(r.scheduler.armed).toBeNull();
    r.tick(WAKE_MIN_INTERVAL_MS);
    r.coord.onMessage(msg("/a@3"));
    expect(r.emits).toEqual(["/a@1"]);
  });
});

// ── Push-delivery coordinator tests (Part 2a) ────────────────────────────

async function flushMicrotasks(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}

function pushRig(opts?: {
  inboxLimits?: { maxMessages: number; maxBytes: number };
  pushLimits?: { maxMessages: number; maxBytes: number };
  maxBatchBytes?: number;
  deliver?: (content: string) => Promise<void>;
  onTransportError?: (err: unknown) => void;
}) {
  const inbox = new BoundedInbox<WakeMessage>(
    jsonByteSize,
    opts?.inboxLimits ?? { maxMessages: 100, maxBytes: 1_000_000 },
  );
  const pushQueue = new BoundedInbox<WakeMessage>(
    jsonByteSize,
    opts?.pushLimits ?? { maxMessages: 100, maxBytes: 1_000_000 },
  );
  const gate = new WakeGate(WAKE_MIN_INTERVAL_MS);
  const scheduler = new FakeScheduler();
  const delivered: string[] = [];
  const errors: unknown[] = [];
  const transport: PushDeliveryTransport = {
    deliver: opts?.deliver ?? (async (content: string) => { delivered.push(content); }),
  };
  let clock = 10_000;
  const coord = createPushDeliveryCoordinator({
    inbox,
    pushQueue,
    gate,
    transport,
    scheduler,
    maxBatchBytes: opts?.maxBatchBytes,
    now: () => clock,
    onTransportError: opts?.onTransportError ?? ((err) => errors.push(err)),
  });
  return {
    inbox,
    pushQueue,
    coord,
    delivered,
    errors,
    scheduler,
    tick: (ms: number) => { clock += ms; },
  };
}

describe("createPushDeliveryCoordinator (hybrid push-turn delivery)", () => {
  test("local envelope pushes directly as already-drained turn and NEVER duplicates into get_messages", async () => {
    const r = pushRig();
    r.coord.onMessage({ from: "/proj@peer", body: { task: "run tests" }, id: "uuid-1", re: "uuid-0", at: "2026-11-19T17:00:00Z" });
    await flushMicrotasks();

    expect(r.delivered).toHaveLength(1);
    const payload = r.delivered[0]!;
    expect(payload).toContain("push-delivered");
    expect(payload).toContain("do not call get_messages");
    expect(payload).toContain("from=/proj@peer re=uuid-0");
    expect(payload).toContain("id=uuid-1");
    expect(payload).toContain('{"task":"run tests"}');

    // Dedicated push queue invariant: get_messages inbox stayed completely empty.
    expect(r.inbox.drain()).toEqual({ items: [], dropped: 0 });
    expect(r.pushQueue.length).toBe(0);
  });

  test("cross-PC, base64-prefixed PC, and _relay envelopes stay in get_messages and never push", async () => {
    const r = pushRig();
    r.coord.onMessage(msg("laptop:/x@y", "remote-1", "r1"));
    r.coord.onMessage(msg("/wAAAAAA:/tmp/r@p", "remote-2", "r2"));
    r.coord.onMessage(msg("_relay", { type: "transport_error" }, "r3"));
    await flushMicrotasks();

    expect(r.delivered).toEqual([]);
    expect(r.scheduler.armed).toBeNull();
    expect(r.pushQueue.length).toBe(0);
    expect(r.inbox.drain().items.map((m) => m.id)).toEqual(["r1", "r2", "r3"]);
  });

  test("hybrid traffic keeps local pushed and remote buffered without cross-contamination", async () => {
    const r = pushRig();
    r.coord.onMessage(msg("laptop:/x@y", "from-remote", "r1"));
    r.coord.onMessage(msg("/local@peer", "from-local", "l1"));
    await flushMicrotasks();

    expect(r.delivered).toHaveLength(1);
    expect(r.delivered[0]).toContain("from-local");
    expect(r.delivered[0]).not.toContain("from-remote");

    const drained = r.inbox.drain();
    expect(drained.items.map((m) => m.id)).toEqual(["r1"]);
  });

  test("rate-capped burst batches into one deferred push after 5s cap without entering inbox", async () => {
    const r = pushRig();
    r.coord.onMessage(msg("/a@1", "first", "id-1")); // immediate push at t=10_000
    await flushMicrotasks();
    expect(r.delivered).toHaveLength(1);

    // Burst during the 5s cap window: queued in pushQueue, timer armed once.
    r.tick(500);
    r.coord.onMessage(msg("/a@2", "second", "id-2"));
    r.tick(500);
    r.coord.onMessage(msg("/a@3", "third", "id-3"));
    r.tick(500);
    r.coord.onMessage(msg("/a@4", "fourth", "id-4"));
    await flushMicrotasks();

    expect(r.delivered).toHaveLength(1);
    expect(r.scheduler.armed).not.toBeNull();
    expect(r.scheduler.armed!.delayMs).toBe(WAKE_MIN_INTERVAL_MS - 500);
    expect(r.inbox.length).toBe(0);

    // Past the 5s window: deferred fire pushes [id-2, id-3, id-4] as ONE batch.
    r.tick(WAKE_MIN_INTERVAL_MS);
    r.scheduler.armed!.fire();
    await flushMicrotasks();

    expect(r.delivered).toHaveLength(2);
    expect(r.delivered[1]).toContain("3 mesh messages");
    expect(r.delivered[1]).toContain("id=id-2");
    expect(r.delivered[1]).toContain("id=id-3");
    expect(r.delivered[1]).toContain("id=id-4");
    expect(r.inbox.drain()).toEqual({ items: [], dropped: 0 });
  });

  test("burst exceeding maxBatchBytes splits cleanly across rate-cap windows using UTF-8 bytes", async () => {
    // Each message block with 40x 'é' (80 UTF-8 bytes) renders to ~115 bytes.
    // Single header is ~127 bytes; 2-msg header is ~135 bytes.
    // A 340-byte cap fits 1 message (~242 B), NOT 2 messages (~367 B).
    const body = "é".repeat(40);
    const r = pushRig({ maxBatchBytes: 340 });

    r.coord.onMessage(msg("/a@1", "kickoff", "id-0")); // immediate push at t=10_000
    await flushMicrotasks();
    expect(r.delivered).toHaveLength(1);

    r.tick(100);
    r.coord.onMessage(msg("/a@1", body, "id-1"));
    r.coord.onMessage(msg("/a@2", body, "id-2"));
    await flushMicrotasks();
    expect(r.scheduler.armed).not.toBeNull();

    // First deferred window: only id-1 fits <= 340 UTF-8 bytes; id-2 re-arms.
    r.tick(WAKE_MIN_INTERVAL_MS);
    r.scheduler.armed!.fire();
    await flushMicrotasks();

    expect(r.delivered).toHaveLength(2);
    expect(Buffer.byteLength(r.delivered[1]!, "utf8")).toBeLessThanOrEqual(340);
    expect(r.delivered[1]).toContain("id=id-1");
    expect(r.delivered[1]).not.toContain("id=id-2");
    expect(r.scheduler.armed).not.toBeNull(); // liveness for remaining id-2

    // Second deferred window: id-2 flushes cleanly.
    r.tick(WAKE_MIN_INTERVAL_MS);
    r.scheduler.armed!.fire();
    await flushMicrotasks();

    expect(r.delivered).toHaveLength(3);
    expect(Buffer.byteLength(r.delivered[2]!, "utf8")).toBeLessThanOrEqual(340);
    expect(r.delivered[2]).toContain("id=id-2");
    expect(r.inbox.drain()).toEqual({ items: [], dropped: 0 });
  });

  test("oversized single local envelope falls back to inbox with body-free pointer and no duplication on failure", async () => {
    let shouldFail = false;
    const delivered: string[] = [];
    const r = pushRig({
      maxBatchBytes: 250,
      deliver: async (content) => {
        if (shouldFail) throw new Error("channel down");
        delivered.push(content);
      },
    });

    const huge = msg("/local@big", "x".repeat(400), "big-1");
    r.coord.onMessage(huge);
    await flushMicrotasks();

    // Moved into inbox and a compact body-free pointer was delivered.
    expect(delivered).toHaveLength(1);
    expect(delivered[0]).toBe(oversizedPushNudgeContent("/local@big"));
    expect(delivered[0]).not.toContain("xxxx");
    expect(r.inbox.drain().items.map((m) => m.id)).toEqual(["big-1"]);

    // Even when the pointer transport ALSO fails, the oversized envelope lands
    // in inbox exactly ONCE (no duplicate rollback).
    shouldFail = true;
    r.tick(WAKE_MIN_INTERVAL_MS);
    r.coord.onMessage(msg("/local@big2", "y".repeat(400), "big-2"));
    await flushMicrotasks();

    expect(r.errors).toHaveLength(1);
    expect(r.inbox.drain().items.map((m) => m.id)).toEqual(["big-2"]);
  });

  test("transport rejection rolls back the unsent batch into get_messages without silent loss", async () => {
    let failNext = true;
    const delivered: string[] = [];
    const r = pushRig({
      deliver: async (content) => {
        if (failNext) throw new Error("stdio broken");
        delivered.push(content);
      },
    });

    // First local message fails transport -> rolls back to inbox.
    r.coord.onMessage(msg("/a@1", "important-1", "id-1"));
    await flushMicrotasks();

    expect(delivered).toEqual([]);
    expect(r.errors).toHaveLength(1);
    expect(r.inbox.drain().items.map((m) => m.id)).toEqual(["id-1"]);

    // Transport recovers after cap window -> next local batch delivers normally.
    failNext = false;
    r.tick(WAKE_MIN_INTERVAL_MS);
    r.coord.onMessage(msg("/a@2", "important-2", "id-2"));
    await flushMicrotasks();

    expect(delivered).toHaveLength(1);
    expect(delivered[0]).toContain("id=id-2");
    expect(r.inbox.drain()).toEqual({ items: [], dropped: 0 });
  });

  test("synchronous transport throw also rolls back safely into get_messages", async () => {
    const r = pushRig({
      deliver: () => { throw new Error("sync boom"); },
    });
    r.coord.onMessage(msg("/a@1", "payload", "id-sync"));
    await flushMicrotasks();

    expect(r.errors).toHaveLength(1);
    expect(r.inbox.drain().items.map((m) => m.id)).toEqual(["id-sync"]);
  });

  test("in-flight async transport serializes batches FIFO without overlapping sends", async () => {
    const pending: Array<{ content: string; resolve: () => void }> = [];
    const r = pushRig({
      deliver: (content) =>
        new Promise<void>((resolve) => {
          pending.push({ content, resolve });
        }),
    });

    // Batch 1 starts and stays in-flight.
    r.coord.onMessage(msg("/a@1", "first", "id-1"));
    expect(pending).toHaveLength(1);
    expect(pending[0]!.content).toContain("id=id-1");

    // Even after 5s+ elapses while batch 1 is still in-flight, batch 2 waits.
    r.tick(WAKE_MIN_INTERVAL_MS + 1_000);
    r.coord.onMessage(msg("/a@2", "second", "id-2"));
    expect(pending).toHaveLength(1);

    // Once batch 1 resolves, batch 2 flushes immediately (cap window already elapsed).
    pending[0]!.resolve();
    await flushMicrotasks();
    expect(pending).toHaveLength(2);
    expect(pending[1]!.content).toContain("id=id-2");

    pending[1]!.resolve();
    await flushMicrotasks();
    expect(r.inbox.drain()).toEqual({ items: [], dropped: 0 });
  });

  test("draining get_messages (onDrain) does NOT cancel a pending deferred local push timer", async () => {
    const r = pushRig();
    r.coord.onMessage(msg("/a@1", "m1", "id-1")); // immediate push
    await flushMicrotasks();

    r.tick(1_000);
    r.coord.onMessage(msg("/a@2", "m2", "id-2")); // capped, armed in pushQueue
    r.coord.onMessage(msg("laptop:/r@1", "remote", "r-1")); // buffered in inbox
    expect(r.scheduler.armed).not.toBeNull();

    // Agent calls get_messages to read remote traffic.
    expect(r.inbox.drain().items.map((m) => m.id)).toEqual(["r-1"]);
    r.coord.onDrain();

    // Deferred push timer for /a@2 MUST still be armed!
    expect(r.scheduler.cancelled).toBe(0);
    expect(r.scheduler.armed).not.toBeNull();

    r.tick(WAKE_MIN_INTERVAL_MS);
    r.scheduler.armed!.fire();
    await flushMicrotasks();
    expect(r.delivered).toHaveLength(2);
    expect(r.delivered[1]).toContain("id=id-2");
  });

  test("push-queue overflow sheds oldest local messages and surfaces drop warning in next batch", async () => {
    const r = pushRig({ pushLimits: { maxMessages: 2, maxBytes: 1_000_000 } });
    r.coord.onMessage(msg("/a@1", "kickoff", "id-0"));
    await flushMicrotasks();

    r.tick(500);
    r.coord.onMessage(msg("/a@1", "dropped", "id-1"));
    r.coord.onMessage(msg("/a@2", "kept-1", "id-2"));
    r.coord.onMessage(msg("/a@3", "kept-2", "id-3")); // sheds id-1

    r.tick(WAKE_MIN_INTERVAL_MS);
    r.scheduler.armed!.fire();
    await flushMicrotasks();

    expect(r.delivered).toHaveLength(2);
    expect(r.delivered[1]).toContain("⚠ 1 earlier local message(s) shed");
    expect(r.delivered[1]).not.toContain("id=id-1");
    expect(r.delivered[1]).toContain("id=id-2");
    expect(r.delivered[1]).toContain("id=id-3");
  });

  test("early timer fire inside cap window re-arms without forcing or dropping queued locals", async () => {
    const r = pushRig();
    r.coord.onMessage(msg("/a@1", "m1", "id-1"));
    await flushMicrotasks();

    r.tick(1_000);
    r.coord.onMessage(msg("/a@2", "m2", "id-2"));
    r.tick(1_000); // still inside 5s cap
    r.scheduler.armed!.fire();
    await flushMicrotasks();

    expect(r.delivered).toHaveLength(1);
    expect(r.scheduler.armed).not.toBeNull();

    r.tick(WAKE_MIN_INTERVAL_MS);
    r.scheduler.armed!.fire();
    await flushMicrotasks();
    expect(r.delivered).toHaveLength(2);
    expect(r.delivered[1]).toContain("id=id-2");
  });

  test("dispose cancels timers and suppresses re-arming when in-flight delivery settles", async () => {
    const pending: Array<() => void> = [];
    const r = pushRig({
      deliver: () => new Promise<void>((resolve) => { pending.push(resolve); }),
    });
    r.coord.onMessage(msg("/a@1", "m1", "id-1"));
    r.coord.onMessage(msg("/a@2", "m2", "id-2")); // queued while id-1 in-flight
    r.coord.dispose();

    pending[0]!();
    await flushMicrotasks();

    expect(r.scheduler.armed).toBeNull();
    expect(pending).toHaveLength(1); // id-2 was NOT started after dispose
  });

  test("default batch ceiling and oversized pointer escaping match contract", () => {
    expect(PUSH_BATCH_MAX_BYTES).toBe(64 * 1024);
    expect(oversizedPushNudgeContent('/hostile"name\n')).not.toMatch(/\n/);
  });

  test("[review regression] clock advancing across cap boundary between reads does not strand queued locals", async () => {
    // Sequence of clock reads: 10_000 (first push), then 14_999 on gate check
    // (capped by 1ms) followed by 15_000 if a second read occurred. A single
    // sampled timestamp must arm a 1ms deferred timer instead of stranding.
    const timestamps = [10_000, 14_999, 15_000, 15_000];
    let idx = 0;
    const inbox = new BoundedInbox<WakeMessage>(jsonByteSize, { maxMessages: 100, maxBytes: 1_000_000 });
    const pushQueue = new BoundedInbox<WakeMessage>(jsonByteSize, { maxMessages: 100, maxBytes: 1_000_000 });
    const gate = new WakeGate(WAKE_MIN_INTERVAL_MS);
    const scheduler = new FakeScheduler();
    const delivered: string[] = [];
    const coord = createPushDeliveryCoordinator({
      inbox,
      pushQueue,
      gate,
      transport: { deliver: async (c) => { delivered.push(c); } },
      scheduler,
      now: () => timestamps[Math.min(idx++, timestamps.length - 1)]!,
    });

    coord.onMessage(msg("/a@1", "first", "id-1")); // reads 10_000 -> delivers
    await flushMicrotasks();
    expect(delivered).toHaveLength(1);

    coord.onMessage(msg("/a@2", "second", "id-2")); // reads 14_999 -> capped by 1ms -> MUST arm
    await flushMicrotasks();
    expect(scheduler.armed).not.toBeNull();
    expect(scheduler.armed!.delayMs).toBe(1);

    scheduler.armed!.fire(); // reads 15_000 -> delivers
    await flushMicrotasks();
    expect(delivered).toHaveLength(2);
    expect(delivered[1]).toContain("id=id-2");
  });

  test("[review regression] immediate flush after cap window cancels stale deferred timer and re-arms remainder", async () => {
    const body = "x".repeat(80);
    const r = pushRig({ maxBatchBytes: 340 });

    r.coord.onMessage(msg("/a@1", "kickoff", "id-0")); // immediate at t=10_000
    await flushMicrotasks();

    r.tick(1_000);
    r.coord.onMessage(msg("/a@1", body, "id-1")); // capped -> arms timer at t=11_000
    expect(r.scheduler.armed).not.toBeNull();

    // Event loop lags past the 5s window before the stale timer fires, and
    // another local arrives: immediate flush cancels the stale timer, sends
    // id-1, and arms a fresh deferred timer for the byte-capped remainder id-2.
    r.tick(WAKE_MIN_INTERVAL_MS);
    r.coord.onMessage(msg("/a@2", body, "id-2"));
    await flushMicrotasks();

    expect(r.scheduler.cancelled).toBe(1);
    expect(r.delivered).toHaveLength(2);
    expect(r.delivered[1]).toContain("id=id-1");
    expect(r.scheduler.armed).not.toBeNull();
    expect(r.scheduler.armed!.delayMs).toBe(WAKE_MIN_INTERVAL_MS);

    r.tick(WAKE_MIN_INTERVAL_MS);
    r.scheduler.armed!.fire();
    await flushMicrotasks();
    expect(r.delivered).toHaveLength(3);
    expect(r.delivered[2]).toContain("id=id-2");
  });

  test("[review regression] push-queue shed count survives a rejected delivery and surfaces on recovery", async () => {
    let failNext = false;
    const delivered: string[] = [];
    const r = pushRig({
      pushLimits: { maxMessages: 1, maxBytes: 1_000_000 },
      deliver: async (content) => {
        if (failNext) throw new Error("transient failure");
        delivered.push(content);
      },
    });

    r.coord.onMessage(msg("/a@1", "kickoff", "id-0"));
    await flushMicrotasks();

    r.tick(500);
    r.coord.onMessage(msg("/a@1", "shed-me", "id-1"));
    r.coord.onMessage(msg("/a@2", "survive-1", "id-2")); // sheds id-1 (dropped=1)

    failNext = true;
    r.tick(WAKE_MIN_INTERVAL_MS);
    r.scheduler.armed!.fire();
    await flushMicrotasks();

    // id-2 rolled back to inbox; dropped=1 must NOT be lost.
    expect(r.inbox.drain().items.map((m) => m.id)).toEqual(["id-2"]);

    failNext = false;
    r.tick(WAKE_MIN_INTERVAL_MS);
    r.coord.onMessage(msg("/a@3", "after-recovery", "id-3"));
    await flushMicrotasks();

    expect(delivered).toHaveLength(2);
    expect(delivered[1]).toContain("⚠ 1 earlier local message(s) shed");
    expect(delivered[1]).toContain("id=id-3");
  });

  test("throwing onTransportError does not strand queued messages or escape as unhandled rejection", async () => {
    let failFirst = true;
    let firstReject: ((err: Error) => void) | undefined;
    let hookCalls = 0;
    const delivered: string[] = [];
    const r = pushRig({
      deliver: (content) => {
        if (failFirst) {
          failFirst = false;
          return new Promise<void>((_, reject) => {
            firstReject = reject;
          });
        }
        delivered.push(content);
        return Promise.resolve();
      },
      onTransportError: () => {
        hookCalls++;
        throw new Error("diagnostic hook blew up");
      },
    });

    r.coord.onMessage(msg("/a@1", "will-fail", "id-1"));
    // Second local message queues while first delivery is in flight.
    r.coord.onMessage(msg("/a@2", "queued-behind", "id-2"));

    // Reject first delivery -> onTransportError throws, but id-1 must still
    // roll back to inbox and id-2 must still arm/flush after the rate cap.
    firstReject!(new Error("channel disconnected"));
    await flushMicrotasks();

    expect(hookCalls).toBe(1);
    expect(r.inbox.drain().items.map((m) => m.id)).toEqual(["id-1"]);
    expect(r.scheduler.armed).not.toBeNull();

    r.tick(WAKE_MIN_INTERVAL_MS);
    r.scheduler.armed!.fire();
    await flushMicrotasks();

    expect(delivered).toHaveLength(1);
    expect(delivered[0]).toContain("id=id-2");
  });
});

describe("parseMeshServerOptions & buildMcpInstructions", () => {
  test("pushDeliver defaults OFF and activates on --push-deliver or OUTPOST_PI_MCP_PUSH_DELIVER=1", () => {
    expect(parseMeshServerOptions([], {}, "/default").pushDeliver).toBe(false);
    expect(parseMeshServerOptions([], { OUTPOST_PI_MCP_PUSH_DELIVER: "0" }, "/default").pushDeliver).toBe(false);
    expect(parseMeshServerOptions([], { OUTPOST_PI_MCP_PUSH_DELIVER: "true" }, "/default").pushDeliver).toBe(false);
    expect(parseMeshServerOptions([], { OUTPOST_PI_MCP_PUSH_DELIVER: "1" }, "/default").pushDeliver).toBe(true);
    expect(parseMeshServerOptions(["--push-deliver"], {}, "/default").pushDeliver).toBe(true);

    const parsed = parseMeshServerOptions(
      ["--cwd", "/custom", "--name", "worker", "--no-bridge", "--push-deliver"],
      {},
      "/default",
    );
    expect(parsed).toEqual({
      cwd: "/custom",
      nameOverride: "worker",
      bridgeEnabled: false,
      pushDeliver: true,
    });
  });

  test("MCP instructions frame delivery generically by mode without Claude-specific wording", () => {
    const inboxMode = buildMcpInstructions("agent-a", false);
    expect(inboxMode).toContain("inbox-drained");
    expect(inboxMode).toContain("get_messages");
    expect(inboxMode.toLowerCase()).not.toContain("claude");

    const pushMode = buildMcpInstructions("agent-a", true);
    expect(pushMode).toContain("hybrid push-delivered");
    expect(pushMode).toContain("do NOT call get_messages");
    expect(pushMode).toContain("<pc>:");
    expect(pushMode).toContain("_relay");
    expect(pushMode.toLowerCase()).not.toContain("claude");
  });
});

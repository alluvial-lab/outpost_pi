import { EventEmitter } from "node:events";
import { describe, expect, test, vi } from "vitest";
import {
  createRelayTransportPort,
  decodeRelayControlFrame,
  MAX_PENDING_RELAY_CONTROL_BYTES,
  MAX_PENDING_RELAY_CONTROL_FRAMES,
  MAX_PENDING_RELAY_DISPATCH_BYTES,
  MAX_PENDING_RELAY_DISPATCH_FRAMES,
} from "./relay_transport.js";
import type { Ed25519Keypair } from "../pairing/crypto.js";
import type { RelayClient } from "../transport/relay_client.js";
import { PiForwardClient } from "../transport/pi_forward_client.js";
import { subscribeRelayIngress } from "../transport/relay_ingress_fanout.js";
import type { RelayDispatchOverflowAudit } from "../transport/relay_dispatch_audit.js";

class FakeRelay extends EventEmitter {
  closed = false;

  async connect(): Promise<void> {
    // connected immediately
  }

  close(): void {
    this.closed = true;
    this.emit("close");
  }

  send = vi.fn();
  sendControl = vi.fn();
}

function makeTransport() {
  const relays: FakeRelay[] = [];
  const auditDispatchOverflow = vi.fn<(event: RelayDispatchOverflowAudit) => void>();
  const transport = createRelayTransportPort({
    createRelay: () => {
      const relay = new FakeRelay();
      relays.push(relay);
      return relay as unknown as RelayClient;
    },
    toWebSocketUrl: (url) => url,
    backoffMs: () => 1,
    now: () => 0,
    setTimer: (cb) => setTimeout(cb, 1),
    clearTimer: (timer) => clearTimeout(timer),
    emitRelayState: vi.fn(),
    auditDispatchOverflow,
  });
  return { transport, relays, auditDispatchOverflow };
}

const keypair = { publicKey: new Uint8Array(32), secretKey: new Uint8Array(64) } as Ed25519Keypair;
const flushDispatch = (): Promise<void> => new Promise((resolve) => setImmediate(resolve));

function outerLine(id: string, payload = id): string {
  return JSON.stringify({ peer: "owner-a", ct: Buffer.from(payload).toString("base64") });
}

function deferred(): { promise: Promise<void>; resolve(): void } {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => { resolve = done; });
  return { promise, resolve };
}

describe("relay transport control frames", () => {
  test("decodes peer presence control frames and rejects outer envelopes", () => {
    expect(decodeRelayControlFrame(JSON.stringify({ type: "peer_offline", peer: "peer-a", since_ts: 123 }))).toEqual({
      type: "peer_offline",
      peer: "peer-a",
      since_ts: 123,
    });
    expect(decodeRelayControlFrame(JSON.stringify({ type: "peer_online", peer: "peer-a" }))).toEqual({
      type: "peer_online",
      peer: "peer-a",
    });
    expect(decodeRelayControlFrame(JSON.stringify({ peer: "peer-a", ct: "abc" }))).toBeNull();
    expect(decodeRelayControlFrame(JSON.stringify({ type: "peer_offline", peer: "peer-a" }))).toBeNull();
  });

  test("dispatches peer_offline and peer_online from the live relay message stream", async () => {
    const { transport, relays } = makeTransport();
    const frames: unknown[] = [];
    transport.onControlFrame((frame) => frames.push(frame));

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    const relay = relays[0]!;

    relay.emit("message", JSON.stringify({ peer: "owner-a", ct: "not-control" }));
    relay.emit("message", JSON.stringify({ type: "peer_offline", peer: "owner-a", since_ts: 111 }));
    relay.emit("message", JSON.stringify({ type: "peer_online", peer: "owner-a" }));
    await flushDispatch();

    expect(frames).toEqual([
      { type: "peer_offline", peer: "owner-a", since_ts: 111 },
      { type: "peer_online", peer: "owner-a" },
    ]);
  });

  test("decodes presence frames and tolerates null/absent since_ts", () => {
    // Valid presence with mixed since_ts: present, null, and absent.
    expect(decodeRelayControlFrame(JSON.stringify({
      type: "presence",
      states: [
        { peer: "peer-a", online: true, since_ts: 5 },
        { peer: "peer-b", online: false, since_ts: null },
        { peer: "peer-c", online: true },
      ],
    }))).toEqual({
      type: "presence",
      states: [
        { peer: "peer-a", online: true, since_ts: 5 },
        { peer: "peer-b", online: false, since_ts: null },
        { peer: "peer-c", online: true },
      ],
    });
  });

  test("rejects malformed presence frames (fail-fast at the boundary)", () => {
    // Non-array states.
    expect(decodeRelayControlFrame(JSON.stringify({ type: "presence", states: "nope" }))).toBeNull();
    // Any malformed entry rejects the WHOLE frame (not silently dropped).
    expect(decodeRelayControlFrame(JSON.stringify({
      type: "presence",
      states: [
        { peer: "peer-a", online: true },
        { peer: "", online: false }, // empty peer
      ],
    }))).toBeNull();
    expect(decodeRelayControlFrame(JSON.stringify({
      type: "presence",
      states: [
        { peer: "peer-a", online: "yes" }, // non-boolean online
      ],
    }))).toBeNull();
    expect(decodeRelayControlFrame(JSON.stringify({
      type: "presence",
      states: [
        { peer: "peer-a", online: true, since_ts: "when" }, // non-number since_ts
      ],
    }))).toBeNull();
  });

  test("dispatchRelayMessage routes each typed frame to only its owning handlers", async () => {
    const { transport, relays } = makeTransport();
    const outerFrames: unknown[] = [];
    transport.onOuterMessage((ingress) => { outerFrames.push(ingress); });

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    const relay = relays[0]!;

    relay.emit("message", JSON.stringify({ type: "peer_offline", peer: "owner-a", since_ts: 1 }));
    relay.emit("message", JSON.stringify({ peer: "owner-a", ct: "ZW52ZWxvcGU=" }));
    await flushDispatch();

    expect(outerFrames).toEqual([{
      kind: "outer",
      frame: { peer: "owner-a", ct: "ZW52ZWxvcGU=" },
      payloadUtf8: "envelope",
    }]);
  });

  test("decodes once before typed fanout to owner, peer, and cross-PC listeners", async () => {
    const { transport, relays } = makeTransport();
    const ownerIngress: unknown[] = [];
    const ownerMessages: unknown[] = [];
    transport.onOuterMessage((ingress) => { ownerIngress.push(ingress); });

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    const relay = relays[0]!;
    const channelA = transport.createPeerChannel({
      peerId: "owner-a",
      onMessage: (message) => ownerMessages.push(message),
      onDisconnect: vi.fn(),
    });
    const channelB = transport.createPeerChannel({
      peerId: "owner-b",
      onMessage: (message) => ownerMessages.push(message),
      onDisconnect: vi.fn(),
    });
    const piForward = new PiForwardClient(relay as unknown as RelayClient);
    const crossPcEnvelopes: unknown[] = [];
    piForward.on("envelope", (envelope) => crossPcEnvelopes.push(envelope));

    // The transport owns the sole raw listener regardless of typed listener count.
    expect(relay.listenerCount("message")).toBe(1);

    const clientMessage = { type: "ping", id: "ping-1" } as const;
    relay.emit("message", JSON.stringify({
      peer: "owner-a",
      ct: Buffer.from(JSON.stringify(clientMessage)).toString("base64"),
    }));
    const crossPcEnvelope = {
      from: "remote:agent",
      to: "local:agent",
      id: "01976000-0000-7000-8000-000000000000",
      re: null,
      body: { hello: "world" },
    };
    relay.emit("message", JSON.stringify({
      type: "pi_envelope_in",
      from_pc: "remote-pc",
      to_room: "room-1",
      envelope: crossPcEnvelope,
    }));
    await flushDispatch();

    expect(ownerIngress).toHaveLength(1);
    expect(ownerMessages).toEqual([clientMessage]);
    expect(crossPcEnvelopes).toEqual([crossPcEnvelope]);
    expect(relay.listenerCount("message")).toBe(1);

    channelA.detach();
    channelB.detach();
    piForward.detach();
    transport.stop();
  });

  test("publishes room controls to the attached cross-PC bridge", async () => {
    const { transport, relays } = makeTransport();
    await transport.start({ relayUrl: "ws://relay.test", keypair });
    const relay = relays[0]!;
    const piForward = new PiForwardClient(relay as unknown as RelayClient);
    const rooms: unknown[] = [];
    piForward.on("rooms", (frame) => rooms.push(frame));
    const snapshot = {
      type: "rooms",
      peer: "remote-pc",
      rooms: [{ room_id: "remote-room", working: false, started_at: 1 }],
    } as const;

    relay.emit("message", JSON.stringify(snapshot));
    await flushDispatch();

    expect(rooms).toEqual([snapshot]);
    piForward.detach();
    transport.stop();
  });

  test("consumed pairing ingress is not republished to post-key channel fanout", async () => {
    const { transport, relays } = makeTransport();
    transport.onOuterMessage(async () => true);

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    const relay = relays[0]!;
    const republished: unknown[] = [];
    const unsubscribe = subscribeRelayIngress(
      relay as unknown as RelayClient,
      (ingress) => republished.push(ingress),
    );

    relay.emit("message", JSON.stringify({
      peer: Buffer.alloc(32, 1).toString("base64"),
      room: "main",
      ct: Buffer.from(JSON.stringify({
        type: "pair_request",
        id: "pair-1",
        token_id: Buffer.alloc(16, 2).toString("base64"),
        pair_mac: Buffer.alloc(32, 3).toString("base64"),
        device_name: "Phone",
        dh_pk: Buffer.alloc(32, 4).toString("base64"),
        dh_sig: Buffer.alloc(64, 5).toString("base64"),
      })).toString("base64"),
    }));
    await flushDispatch();

    // No post-key subscriber sees the plaintext pair_request, so it cannot
    // generate the prior false-positive plaintext_post_key audit event.
    expect(republished).toEqual([]);
    unsubscribe();
    transport.stop();
  });

  test("outer-message freshness expires on relay replacement and close", async () => {
    const { transport, relays } = makeTransport();
    const freshness: Array<() => boolean> = [];
    transport.onOuterMessage((_line, isCurrent) => freshness.push(isCurrent));

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    expect(relays[0]!.listenerCount("message")).toBe(1);
    relays[0]!.emit("message", JSON.stringify({ peer: "owner-a", ct: "Zmlyc3Q=" }));
    await flushDispatch();
    expect(freshness[0]?.()).toBe(true);

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    expect(freshness[0]?.()).toBe(false);
    expect(relays[0]!.listenerCount("message")).toBe(0);
    expect(relays[1]!.listenerCount("message")).toBe(1);
    relays[1]!.emit("message", JSON.stringify({ peer: "owner-a", ct: "c2Vjb25k" }));
    await flushDispatch();
    expect(freshness[1]?.()).toBe(true);

    relays[1]!.emit("close");
    expect(freshness[1]?.()).toBe(false);
    expect(relays[1]!.listenerCount("message")).toBe(0);
    transport.stop();
  });

  test("bounds a blocked data-plane FIFO and preserves accepted cross-class order", async () => {
    const { transport, relays, auditDispatchOverflow } = makeTransport();
    const blocker = deferred();
    const dispatched: string[] = [];
    const controls: unknown[] = [];
    transport.onOuterMessage(async (ingress) => {
      dispatched.push(ingress.payloadUtf8);
      if (dispatched.length === 1) await blocker.promise;
    });
    transport.onControlFrame((frame) => { controls.push(frame); });

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    const relay = relays[0]!;
    const droppedByFlood = 201;
    const floodSize = MAX_PENDING_RELAY_DISPATCH_FRAMES + droppedByFlood;
    const floodLines = Array.from({ length: floodSize }, (_, index) => outerLine(String(index)));
    for (const line of floodLines) relay.emit("message", line);
    relay.emit("message", JSON.stringify({ type: "peer_online", peer: "owner-a" }));
    await flushDispatch();

    expect(dispatched).toEqual(["0"]);
    expect(controls).toEqual([]);
    expect(auditDispatchOverflow).toHaveBeenCalled();
    expect(auditDispatchOverflow.mock.calls.length).toBeLessThan(droppedByFlood);
    expect(
      auditDispatchOverflow.mock.calls.reduce(
        (total, [event]) => total + (event.queue === "data" ? event.droppedFrames : 0),
        0,
      ),
    ).toBe(droppedByFlood);
    expect(
      auditDispatchOverflow.mock.calls.reduce(
        (total, [event]) => total + (event.queue === "data" ? event.droppedBytes : 0),
        0,
      ),
    ).toBe(
      floodLines.slice(MAX_PENDING_RELAY_DISPATCH_FRAMES).reduce(
        (total, line) => total + Buffer.byteLength(line, "utf8"),
        0,
      ),
    );

    blocker.resolve();
    await flushDispatch();
    expect(dispatched).toEqual(
      Array.from({ length: MAX_PENDING_RELAY_DISPATCH_FRAMES }, (_, index) => String(index)),
    );
    expect(controls).toEqual([{ type: "peer_online", peer: "owner-a" }]);
    transport.stop();
  });

  test("bounds and coalesces audit for a blocked control-frame flood", async () => {
    const { transport, relays, auditDispatchOverflow } = makeTransport();
    const blocker = deferred();
    const controls: string[] = [];
    transport.onControlFrame(async (frame) => {
      if (frame.type === "peer_online") controls.push(frame.peer);
      if (controls.length === 1) await blocker.promise;
    });

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    const relay = relays[0]!;
    const droppedByFlood = 201;
    for (let index = 0; index < MAX_PENDING_RELAY_CONTROL_FRAMES + droppedByFlood; index += 1) {
      relay.emit("message", JSON.stringify({ type: "peer_online", peer: `owner-${index}` }));
    }
    await flushDispatch();

    expect(controls).toEqual(["owner-0"]);
    const controlAudits = auditDispatchOverflow.mock.calls
      .map(([event]) => event)
      .filter((event) => event.queue === "control");
    expect(controlAudits.length).toBeGreaterThan(0);
    expect(controlAudits.length).toBeLessThan(droppedByFlood);
    expect(controlAudits.reduce((total, event) => total + event.droppedFrames, 0)).toBe(droppedByFlood);
    expect(controlAudits.every((event) =>
      event.maxPendingFrames === MAX_PENDING_RELAY_CONTROL_FRAMES &&
      event.maxPendingBytes === MAX_PENDING_RELAY_CONTROL_BYTES
    )).toBe(true);

    blocker.resolve();
    await flushDispatch();
    expect(controls).toEqual(
      Array.from({ length: MAX_PENDING_RELAY_CONTROL_FRAMES }, (_, index) => `owner-${index}`),
    );
    transport.stop();
  });

  test("bounds retained control bytes independently of frame count", async () => {
    const { transport, relays, auditDispatchOverflow } = makeTransport();
    const blocker = deferred();
    const controls: unknown[] = [];
    transport.onControlFrame(async (frame) => {
      controls.push(frame);
      if (controls.length === 1) await blocker.promise;
    });

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    const relay = relays[0]!;
    const line = JSON.stringify({ type: "peer_online", peer: "x".repeat(64 * 1024) });
    const lineBytes = Buffer.byteLength(line, "utf8");
    const acceptedByBytes = Math.floor(MAX_PENDING_RELAY_CONTROL_BYTES / lineBytes);
    expect(acceptedByBytes).toBeLessThan(MAX_PENDING_RELAY_CONTROL_FRAMES);

    for (let index = 0; index < acceptedByBytes + 3; index += 1) relay.emit("message", line);
    await flushDispatch();
    expect(controls).toHaveLength(1);
    await vi.waitFor(() => expect(auditDispatchOverflow.mock.calls.reduce(
      (total, [event]) => total + (event.queue === "control" ? event.droppedFrames : 0),
      0,
    )).toBe(3));

    blocker.resolve();
    await flushDispatch();
    expect(controls).toHaveLength(acceptedByBytes);
    transport.stop();
  });

  test("unbind releases a blocked generation and the replacement dispatches independently", async () => {
    const { transport, relays } = makeTransport();
    const blocker = deferred();
    const dispatched: string[] = [];
    transport.onOuterMessage(async (ingress) => {
      dispatched.push(ingress.payloadUtf8);
      if (ingress.payloadUtf8 === "old-0") await blocker.promise;
    });

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    for (let index = 0; index < MAX_PENDING_RELAY_DISPATCH_FRAMES; index += 1) {
      relays[0]!.emit("message", outerLine(`old-${index}`));
    }
    await flushDispatch();
    expect(dispatched).toEqual(["old-0"]);

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    relays[1]!.emit("message", outerLine("new-0"));
    await flushDispatch();
    expect(dispatched).toEqual(["old-0", "new-0"]);

    blocker.resolve();
    await flushDispatch();
    expect(dispatched).toEqual(["old-0", "new-0"]);
    transport.stop();
  });

  test("async owner-handler rejection is observed and later frames keep routing", async () => {
    const { transport, relays, auditDispatchOverflow } = makeTransport();
    const dispatched: string[] = [];
    const unhandled = vi.fn();
    process.on("unhandledRejection", unhandled);
    try {
      transport.onOuterMessage(async (ingress) => {
        dispatched.push(ingress.payloadUtf8);
        if (ingress.payloadUtf8 === "reject") throw new Error("owner lookup failed");
      });

      await transport.start({ relayUrl: "ws://relay.test", keypair });
      relays[0]!.emit("message", outerLine("reject"));
      relays[0]!.emit("message", outerLine("healthy"));
      await flushDispatch();
      await flushDispatch();

      expect(dispatched).toEqual(["reject", "healthy"]);
      expect(unhandled).not.toHaveBeenCalled();
      expect(auditDispatchOverflow).not.toHaveBeenCalled();
      transport.stop();
    } finally {
      process.removeListener("unhandledRejection", unhandled);
    }
  });

  test("dispatch errors and reconnect cycles do not drift generation accounting", async () => {
    const { transport, relays, auditDispatchOverflow } = makeTransport();
    const dispatched: string[] = [];
    transport.onOuterMessage((ingress) => {
      dispatched.push(ingress.payloadUtf8);
      if (ingress.payloadUtf8.startsWith("fail-")) throw new Error("handler failed");
    });

    for (let generation = 0; generation < 3; generation += 1) {
      await transport.start({ relayUrl: "ws://relay.test", keypair });
      const current = relays[generation]!;
      for (let batch = 0; batch < 2; batch += 1) {
        for (let index = 0; index < 200; index += 1) {
          current.emit("message", outerLine(`fail-${generation}-${batch}-${index}`));
        }
        await flushDispatch();
      }
    }
    relays[2]!.emit("message", outerLine("healthy"));
    await flushDispatch();

    expect(dispatched.at(-1)).toBe("healthy");
    expect(auditDispatchOverflow).not.toHaveBeenCalled();
    transport.stop();
  });

  test("bounds pending raw bytes before chaining another data-plane frame", async () => {
    const { transport, relays, auditDispatchOverflow } = makeTransport();
    const blocker = deferred();
    const dispatched: string[] = [];
    transport.onOuterMessage(async (ingress) => {
      dispatched.push(ingress.payloadUtf8);
      if (dispatched.length === 1) await blocker.promise;
    });

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    const relay = relays[0]!;
    const payload = "x".repeat(1024 * 1024);
    const line = outerLine("large", payload);
    const lineBytes = Buffer.byteLength(line, "utf8");
    const acceptedByBytes = Math.floor(MAX_PENDING_RELAY_DISPATCH_BYTES / lineBytes);
    expect(acceptedByBytes).toBeLessThan(MAX_PENDING_RELAY_DISPATCH_FRAMES);

    for (let index = 0; index < acceptedByBytes + 3; index += 1) {
      relay.emit("message", line);
    }
    await flushDispatch();
    expect(dispatched).toHaveLength(1);
    await vi.waitFor(() => expect(
      auditDispatchOverflow.mock.calls.reduce(
        (total, [event]) => total + (event.queue === "data" ? event.droppedFrames : 0),
        0,
      ),
    ).toBe(3));

    blocker.resolve();
    await flushDispatch();
    expect(dispatched).toHaveLength(acceptedByBytes);
    transport.stop();
  });

  test("dispatches a legitimate reconnect burst completely and in FIFO order", async () => {
    const { transport, relays, auditDispatchOverflow } = makeTransport();
    const dispatched: string[] = [];
    transport.onOuterMessage((ingress) => {
      const message = JSON.parse(ingress.payloadUtf8) as { id: string };
      dispatched.push(message.id);
    });

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    const relay = relays[0]!;
    const expected = Array.from({ length: 50 }, (_, index) => `queued-${index}`);
    for (const id of expected) {
      relay.emit("message", outerLine(id, JSON.stringify({
        type: "user_message",
        id,
        session_id: "session-current",
        text: `message ${id}`,
      })));
    }
    await flushDispatch();

    expect(dispatched).toEqual(expected);
    expect(auditDispatchOverflow).not.toHaveBeenCalled();
    transport.stop();
  });

  test("room metadata updates emit the generated frame's exact wire shape", async () => {
    const { transport, relays } = makeTransport();
    await transport.start({ relayUrl: "ws://relay.test", keypair, roomId: "room-1" });

    transport.sendRoomMeta({ model: "model-1", thinking: "high", working: false });

    expect(relays[0]!.sendControl).toHaveBeenCalledWith({
      type: "room_meta_update",
      room_id: "room-1",
      meta: { model: "model-1", thinking: "high", working: false },
    });
    transport.stop();
  });

  test("presence subscription emits the canonical control frame", async () => {
    const { transport, relays } = makeTransport();
    await transport.start({ relayUrl: "ws://relay.test", keypair });

    transport.subscribePresence(["owner-a", "owner-b"]);

    expect(relays[0]!.sendControl).toHaveBeenCalledWith({
      type: "subscribe_presence",
      peers: ["owner-a", "owner-b"],
    });
    transport.stop();
  });
});

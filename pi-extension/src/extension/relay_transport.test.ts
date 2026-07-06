import { EventEmitter } from "node:events";
import { describe, expect, test, vi } from "vitest";
import { createRelayTransportPort, decodeRelayControlFrame } from "./relay_transport.js";
import type { Ed25519Keypair } from "../pairing/crypto.js";
import type { RelayClient } from "../transport/relay_client.js";

class FakeRelay extends EventEmitter {
  closed = false;

  async connect(): Promise<void> {
    // connected immediately
  }

  close(): void {
    this.closed = true;
    this.emit("close");
  }

  sendControl = vi.fn();
}

function makeTransport() {
  const relays: FakeRelay[] = [];
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
  });
  return { transport, relays };
}

const keypair = { publicKey: new Uint8Array(32), secretKey: new Uint8Array(64) } as Ed25519Keypair;

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

  test("dispatchRelayMessage still forwards raw control-frame lines to outerMessageHandlers", async () => {
    // The raw relay-message path (outerMessageHandlers) must still receive every
    // line — including control frames — so the legacy envelope path is
    // preserved. A control frame lacks `ct`, so decodeOuterEnvelope returns
    // null and it's ignored; the point is the line is still forwarded.
    const { transport, relays } = makeTransport();
    const outerLines: string[] = [];
    transport.onOuterMessage((line) => outerLines.push(line));

    await transport.start({ relayUrl: "ws://relay.test", keypair });
    const relay = relays[0]!;

    relay.emit("message", JSON.stringify({ type: "peer_offline", peer: "owner-a", since_ts: 1 }));
    relay.emit("message", JSON.stringify({ peer: "owner-a", ct: "envelope" }));

    expect(outerLines).toHaveLength(2);
    expect(outerLines[0]).toContain("peer_offline");
    expect(outerLines[1]).toContain("envelope");
  });
});

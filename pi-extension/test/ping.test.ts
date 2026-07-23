/**
 * Ping → Pong roundtrip test.
 *
 * Verifies the full flow: app sends a `ping` ClientMessage over the relay,
 * the extension handler calls `_peerChannel.send({ type: "pong", … })`,
 * and the pong is sent back to the correct peer with the matching id.
 */
import { describe, expect, test, vi, beforeEach } from "vitest";
import { EventEmitter } from "node:events";
import { ed25519 } from "@noble/curves/ed25519.js";
import {
  appTranscript,
  generateX25519Keypair,
  open,
  seal,
} from "../src/transport/secure_channel.js";

const PI_SK = Uint8Array.from(Buffer.from("wLGik4R1ZldIOSob/O3ezb6vkIFyY1RFNicYCRorPE0=", "base64"));
const PI_PK = Uint8Array.from(Buffer.from("SG3JE70hBTj4H924lWhYH+R5bEiXQf+NY/wajPQB30Y=", "base64"));
const OWNER_SK = Uint8Array.from(Buffer.from("TzwrGgkYJzZFVGNygZCvvs3c6/oQKThHVmV0g5KhsM8=", "base64"));
const OWNER_PK = Uint8Array.from(Buffer.from("v1nhFJ53/JSjBQIllm+LS10pyRlN74it+UthdQ/FwbU=", "base64"));
const APP_PEER_ID = Buffer.from(OWNER_PK).toString("base64");
let storedPeer: {
  name: string;
  remote_epk: string;
  paired_at: string;
  channel_key?: string;
  send_seq?: string;
  recv_seq?: string;
} | null = null;
let appSendKey: Uint8Array | null = null;
let appRecvKey: Uint8Array | null = null;
let appSendSeq = 0n;
let appRecvSeq = 0n;

// ── Mock RelayClient ──────────────────────────────────────────────────────────

const relayRef: { current: MockRelay | null } = { current: null };

class MockRelay extends EventEmitter {
  static OPEN = 1;
  readyState = MockRelay.OPEN;
  connect     = vi.fn();
  send        = vi.fn();
  sendControl = vi.fn();
  close       = vi.fn();
  constructor() { super(); relayRef.current = this; }
}

// ── Mock storage (empty — no peer persistence tests here) ─────────────────────

vi.mock("../src/pairing/storage.js", async (importOriginal) => {
  const orig = await importOriginal<typeof import("../src/pairing/storage.js")>();
  return {
    ...orig,
    getOrCreateEd25519Keypair: vi.fn().mockResolvedValue({ publicKey: PI_PK, secretKey: PI_SK }),
    listPeers: vi.fn().mockImplementation(async () => storedPeer ? [storedPeer] : []),
    addPeer: vi.fn().mockImplementation(async (peer: NonNullable<typeof storedPeer>) => {
      storedPeer = peer;
      const material = Buffer.from(peer.channel_key!, "base64");
      appRecvKey = Uint8Array.from(material.subarray(0, 32));
      appSendKey = Uint8Array.from(material.subarray(32, 64));
      appSendSeq = BigInt(peer.recv_seq ?? "0");
      appRecvSeq = BigInt(peer.send_seq ?? "0");
    }),
    updatePeerChannelSequences: vi.fn().mockImplementation(async (
      _peer: string,
      _key: string,
      patch: { sendSeq?: bigint; recvSeq?: bigint },
    ) => {
      if (!storedPeer) return false;
      if (patch.sendSeq !== undefined) storedPeer.send_seq = patch.sendSeq.toString();
      if (patch.recvSeq !== undefined) storedPeer.recv_seq = patch.recvSeq.toString();
      return true;
    }),
    removePeer: vi.fn(),
  };
});

// ── Mock config ───────────────────────────────────────────────────────────────

vi.mock("../src/config.js", async (importOriginal) => {
  const orig = await importOriginal<typeof import("../src/config.js")>();
  return {
    ...orig,
    loadConfig: vi.fn().mockReturnValue({}),
    saveConfig: vi.fn(),
    resolveRelayUrl: vi.fn().mockReturnValue({
      url: "ws://localhost:3000",
      source: "default" as const,
    }),
  };
});

// ── Mock qr ───────────────────────────────────────────────────────────────────

vi.mock("../src/pairing/qr.js", async (importOriginal) => {
  const orig = await importOriginal<typeof import("../src/pairing/qr.js")>();
  return {
    ...orig,
    displayQR: vi.fn(),
    qrSession: {
      issueToken: vi.fn().mockReturnValue({ token: "test-token", expiresAt: Date.now() + 60_000 }),
      consumeToken: vi.fn().mockReturnValue("ok"),
      clear: vi.fn(),
      generateToken: vi.fn().mockReturnValue("test-token"),
    },
  };
});

// Mock RelayClient *after* qr import (so module resolution order is consistent)
vi.mock("../src/transport/relay_client.js", () => ({
  RelayClient: MockRelay,
}));

// ── Import the extension after mocks ──────────────────────────────────────────

const {
  default: extension,
  outpostPiTestHarness,
  _startRelayForTest,
} = await import("../src/index.js");

import type { ExtensionAPI, ExtensionFactory } from "@mariozechner/pi-coding-agent";

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeMockCtx() {
  return { ui: { notify: vi.fn() }, cwd: "/tmp/test", abort: vi.fn() };
}

function makeInnerLine(peer: string, inner: object): string {
  const record = { ...(inner as Record<string, unknown>) };
  const wirePeer = peer === "app-peer-001" ? APP_PEER_ID : peer;
  if (record.type === "pair_request") {
    const dh = generateX25519Keypair();
    const token = String(record.token ?? "");
    record.dh_pk = Buffer.from(dh.pk).toString("base64");
    record.dh_sig = Buffer.from(ed25519.sign(appTranscript(token, dh.pk, PI_PK), OWNER_SK)).toString("base64");
  }
  let payload = Buffer.from(JSON.stringify(record));
  if (record.type !== "pair_request" && wirePeer === APP_PEER_ID && appSendKey) {
    appSendSeq += 1n;
    payload = Buffer.from(seal(appSendKey, appSendSeq, JSON.stringify(record)));
  }
  return JSON.stringify({ peer: wirePeer, ct: payload.toString("base64") });
}

function decodeSentCt(raw: string): { peer: string; inner: Record<string, unknown> } {
  const outer = JSON.parse(raw) as { peer: string; ct: string };
  const frame = Buffer.from(outer.ct, "base64");
  let json: string;
  if (frame[0] === 0x01) {
    if (!appRecvKey) throw new Error("missing app receive key");
    const opened = open(appRecvKey, frame, appRecvSeq);
    if (!opened) throw new Error("failed to open secure pong");
    appRecvSeq = opened.seq;
    json = opened.json;
  } else {
    json = frame.toString("utf8");
  }
  return {
    peer: outer.peer === APP_PEER_ID ? "app-peer-001" : outer.peer,
    inner: JSON.parse(json) as Record<string, unknown>,
  };
}

/**
 * Pair the extension by emitting a `start` command then injecting a
 * `pair_request` via the relay mock.
 */
async function pairUp(): Promise<void> {
  // Bring just the relay up (no UDS mesh — this test is relay-focused).
  // The 2026-05-23 surface cleanup removed `outpost-pi relay start`; the
  // equivalent for tests is `_startRelayForTest`.
  const pi = {
    on: () => undefined,
    registerCommand: () => undefined,
    registerTool: () => undefined,
    registerShortcut: () => undefined,
    registerFlag: () => undefined,
    getFlag: () => undefined,
    registerMessageRenderer: () => undefined,
    sendMessage: () => undefined,
    sendUserMessage: () => undefined,
  } as unknown as ExtensionAPI;
  (extension as ExtensionFactory)(pi);

  await _startRelayForTest(makeMockCtx());
  expect(outpostPiTestHarness.state()).toBe("started");

  // Inject a pair_request
  relayRef.current!.emit("message", makeInnerLine("app-peer-001", {
    type: "pair_request",
    id: "pair-req-1",
    token: "test-token",
    device_name: "Test Phone",
  }));

  // Wait for paired
  await vi.waitFor(() => expect(outpostPiTestHarness.state()).toBe("paired"), { timeout: 2000 });
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("ping → pong roundtrip", () => {
  beforeEach(async () => {
    vi.clearAllMocks();
    relayRef.current = null;
    storedPeer = null;
    appSendKey = null;
    appRecvKey = null;
    appSendSeq = 0n;
    appRecvSeq = 0n;

    // Stop any active session first (idempotent — safe when already idle).
    await outpostPiTestHarness.stop(makeMockCtx());
  });

  test("ping from paired peer → pong sent back with matching in_reply_to", async () => {
    await pairUp();
    expect(outpostPiTestHarness.state()).toBe("paired");

    const sendsBefore = relayRef.current!.send.mock.calls.length;

    // App sends a ping
    relayRef.current!.emit("message", makeInnerLine("app-peer-001", {
      type: "ping",
      id: "ping-abc-123",
    }));

    // Small delay for async handler
    await new Promise((r) => setTimeout(r, 30));

    const sent = relayRef.current!.send.mock.calls
      .slice(sendsBefore)
      .map((c: unknown[]) => c[0] as string);

    // Find pong frames directed to our peer
    const pongs = sent
      .map(decodeSentCt)
      .filter((d) => d.inner.type === "pong");

    expect(pongs).toHaveLength(1);
    expect(pongs[0]!.peer).toBe("app-peer-001");
    expect(pongs[0]!.inner).toMatchObject({
      type: "pong",
      in_reply_to: "ping-abc-123",
    });
  });

  test("ping from unknown peer → no pong sent (ignored by routeClientMessage)", async () => {
    await pairUp();

    const sendsBefore = relayRef.current!.send.mock.calls.length;

    // Unknown peer sends a ping (not the paired one)
    relayRef.current!.emit("message", makeInnerLine("some-rando-peer", {
      type: "ping",
      id: "ping-rando",
    }));

    await new Promise((r) => setTimeout(r, 30));

    const sent = relayRef.current!.send.mock.calls
      .slice(sendsBefore)
      .map((c: unknown[]) => c[0] as string);

    const pongs = sent
      .map(decodeSentCt)
      .filter((d) => d.inner.type === "pong");

    expect(pongs).toHaveLength(0);
  });

  test("two pings → two pongs, each with correct in_reply_to", async () => {
    await pairUp();

    const sendsBefore = relayRef.current!.send.mock.calls.length;

    relayRef.current!.emit("message", makeInnerLine("app-peer-001", {
      type: "ping", id: "ping-001",
    }));
    relayRef.current!.emit("message", makeInnerLine("app-peer-001", {
      type: "ping", id: "ping-002",
    }));

    await new Promise((r) => setTimeout(r, 30));

    const sent = relayRef.current!.send.mock.calls
      .slice(sendsBefore)
      .map((c: unknown[]) => c[0] as string);

    const pongs = sent
      .map(decodeSentCt)
      .filter((d) => d.inner.type === "pong");

    expect(pongs).toHaveLength(2);

    const replyToIds = pongs.map((d) => d.inner["in_reply_to"]);
    expect(replyToIds).toEqual(["ping-001", "ping-002"]);
  });

  test("ping in idle state (no relay) → no crash, no pong", async () => {
    // Don't start at all — state is "idle"
    expect(outpostPiTestHarness.state()).toBe("idle");

    // routeClientMessage with no _peerChannel should return early
    outpostPiTestHarness.routeClientMessage(
      { type: "ping", id: "ping-idle" },
      { abort: vi.fn() },
    );

    // No relay was ever created, so no send could have been called
    expect(relayRef.current).toBeNull();
  });

  test(
    "ping → pong within 5 seconds",
    async () => {
      await pairUp();

      const sendsBefore = relayRef.current!.send.mock.calls.length;

      relayRef.current!.emit("message", makeInnerLine("app-peer-001", {
        type: "ping", id: "ping-5sec",
      }));

      // Wait 5 seconds to ensure async handler completes in time
      await new Promise((r) => setTimeout(r, 5000));

      const sent = relayRef.current!.send.mock.calls
        .slice(sendsBefore)
        .map((c: unknown[]) => c[0] as string);

      const pongs = sent
        .map(decodeSentCt)
        .filter((d) => d.inner.type === "pong");

      expect(pongs).toHaveLength(1);
      expect(pongs[0]!.inner).toMatchObject({
        type: "pong",
        in_reply_to: "ping-5sec",
      });
    },
    10_000,
  );
});
